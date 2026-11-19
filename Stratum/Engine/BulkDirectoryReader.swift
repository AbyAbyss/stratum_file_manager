import Foundation
import Darwin

enum SortField: String, CaseIterable, Sendable {
    case name = "Name"
    case kind = "Kind"
    case modified = "Modified"
    case size = "Size"
}

struct DirectoryLoadBatch: Sendable {
    let items: [FileItem]
    let isInitialFastBatch: Bool
    let isComplete: Bool
    let totalBytes: Int64
}

final class BulkDirectoryReader: Sendable {
    static let shared = BulkDirectoryReader()

    private let ioQueue = DispatchQueue(
        label: "app.stratum.bulk-directory-reader",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "xpc",
        "photoslibrary", "aplibrary", "imovielibrary", "fcpbundle",
        "xcodeproj", "xcworkspace", "playground", "xcarchive",
        "key", "pages", "numbers", "rtfd", "scptd", "logicx"
    ]

    /// Streams directory contents off the Swift cooperative pool using `getattrlistbulk`.
    /// Emits the first 200 items immediately (<16ms) before full sorting completes on large folders,
    /// then emits the complete sorted list.
    func streamDirectory(
        at directoryURL: URL,
        showHidden: Bool,
        sortField: SortField,
        ascending: Bool
    ) -> AsyncStream<DirectoryLoadBatch> {
        AsyncStream { continuation in
            final class CancelFlag: @unchecked Sendable {
                private let lock = NSLock()
                private var _cancelled = false
                var isCancelled: Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    return _cancelled
                }
                func cancel() {
                    lock.lock()
                    _cancelled = true
                    lock.unlock()
                }
            }

            let cancelFlag = CancelFlag()
            continuation.onTermination = { _ in
                cancelFlag.cancel()
            }

            ioQueue.async {
                Self.performBulkRead(
                    directoryURL: directoryURL,
                    showHidden: showHidden,
                    sortField: sortField,
                    ascending: ascending,
                    isCancelled: { cancelFlag.isCancelled },
                    yield: { batch in
                        continuation.yield(batch)
                    },
                    finish: {
                        continuation.finish()
                    }
                )
            }
        }
    }

    /// Synchronous helper for reading a single directory on a background DispatchQueue (used by Column View & tests).
    func readDirectorySync(
        at directoryURL: URL,
        showHidden: Bool,
        sortField: SortField = .name,
        ascending: Bool = true
    ) -> [FileItem] {
        var finalItems: [FileItem] = []
        Self.performBulkRead(
            directoryURL: directoryURL,
            showHidden: showHidden,
            sortField: sortField,
            ascending: ascending,
            isCancelled: { false },
            yield: { batch in
                if batch.isComplete {
                    finalItems = batch.items
                }
            },
            finish: {}
        )
        return finalItems
    }

    private static func performBulkRead(
        directoryURL: URL,
        showHidden: Bool,
        sortField: SortField,
        ascending: Bool,
        isCancelled: () -> Bool,
        yield: (DirectoryLoadBatch) -> Void,
        finish: () -> Void
    ) {
        let dirPath = directoryURL.path
        let fd = Darwin.open(dirPath, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else {
            yield(DirectoryLoadBatch(items: [], isInitialFastBatch: false, isComplete: true, totalBytes: 0))
            finish()
            return
        }
        defer { Darwin.close(fd) }

        var attrList = attrlist()
        attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attrList.commonattr =
            attrgroup_t(bitPattern: Int32(bitPattern: UInt32(ATTR_CMN_RETURNED_ATTRS))) |
            attrgroup_t(ATTR_CMN_NAME) |
            attrgroup_t(ATTR_CMN_OBJTYPE) |
            attrgroup_t(ATTR_CMN_CRTIME) |
            attrgroup_t(ATTR_CMN_MODTIME) |
            attrgroup_t(ATTR_CMN_FLAGS) |
            attrgroup_t(ATTR_CMN_FILEID)
        attrList.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)
        attrList.fileattr = attrgroup_t(ATTR_FILE_TOTALSIZE) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

        let bufSize = 256 * 1024 // 256 KB buffer per syscall
        let attrBuf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
        defer { attrBuf.deallocate() }

        var allItems: [FileItem] = []
        allItems.reserveCapacity(512)
        var totalBytes: Int64 = 0
        var didEmitFastBatch = false

        let now = Date()
        let cal = Calendar.current

        while !isCancelled() {
            let count = getattrlistbulk(fd, &attrList, attrBuf, bufSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            if count <= 0 {
                break
            }

            var entryPtr = attrBuf
            for _ in 0..<count {
                if isCancelled() {
                    finish()
                    return
                }

                let entryLength = Int(entryPtr.load(as: UInt32.self))
                guard entryLength > 0 else { break }
                let nextEntryPtr = entryPtr.advanced(by: entryLength)

                var cursor = entryPtr.advanced(by: 4)
                let returned = cursor.loadUnaligned(as: attribute_set_t.self)
                cursor = cursor.advanced(by: MemoryLayout<attribute_set_t>.size)

                var nameString: String?
                if (returned.commonattr & attrgroup_t(ATTR_CMN_NAME)) != 0 {
                    let refAddr = cursor
                    let ref = cursor.loadUnaligned(as: attrreference_t.self)
                    cursor = cursor.advanced(by: MemoryLayout<attrreference_t>.size)
                    if ref.attr_length > 0 {
                        let cStrPtr = refAddr.advanced(by: Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                        nameString = String(cString: cStrPtr)
                    }
                }

                var objType: UInt32 = 0
                if (returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE)) != 0 {
                    objType = cursor.loadUnaligned(as: UInt32.self)
                    cursor = cursor.advanced(by: 4)
                }

                var crTimeSec: Int = 0
                if (returned.commonattr & attrgroup_t(ATTR_CMN_CRTIME)) != 0 {
                    let ts = cursor.loadUnaligned(as: timespec.self)
                    crTimeSec = ts.tv_sec
                    cursor = cursor.advanced(by: MemoryLayout<timespec>.size)
                }

                var modTimeSec: Int = 0
                if (returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME)) != 0 {
                    let ts = cursor.loadUnaligned(as: timespec.self)
                    modTimeSec = ts.tv_sec
                    cursor = cursor.advanced(by: MemoryLayout<timespec>.size)
                }

                var flags: UInt32 = 0
                if (returned.commonattr & attrgroup_t(ATTR_CMN_FLAGS)) != 0 {
                    flags = cursor.loadUnaligned(as: UInt32.self)
                    cursor = cursor.advanced(by: 4)
                }

                var fileId: UInt64 = 0
                if (returned.commonattr & attrgroup_t(ATTR_CMN_FILEID)) != 0 {
                    fileId = cursor.loadUnaligned(as: UInt64.self)
                    cursor = cursor.advanced(by: 8)
                }

                var dirEntryCount: UInt32?
                if (returned.dirattr & attrgroup_t(ATTR_DIR_ENTRYCOUNT)) != 0 {
                    dirEntryCount = cursor.loadUnaligned(as: UInt32.self)
                    cursor = cursor.advanced(by: 4)
                }

                var logicalSize: Int64 = 0
                if (returned.fileattr & attrgroup_t(ATTR_FILE_TOTALSIZE)) != 0 {
                    logicalSize = cursor.loadUnaligned(as: Int64.self)
                    cursor = cursor.advanced(by: 8)
                }

                var allocSize: Int64 = 0
                if (returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE)) != 0 {
                    allocSize = cursor.loadUnaligned(as: Int64.self)
                    cursor = cursor.advanced(by: 8)
                }

                entryPtr = nextEntryPtr

                guard let name = nameString, !name.isEmpty, name != ".", name != ".." else {
                    continue
                }
                if name == ".DS_Store" {
                    continue
                }

                let isHidden = name.hasPrefix(".") || (flags & UInt32(UF_HIDDEN)) != 0
                if !showHidden && isHidden {
                    continue
                }

                // Cloud stub safety: SF_DATALESS = 0x40000000
                let isDataless = (flags & UInt32(SF_DATALESS)) != 0

                // VREG = 1, VDIR = 2, VLNK = 5
                let isDir = (objType == 2)
                let isSymlink = (objType == 5)
                let rawExt = (name as NSString).pathExtension.lowercased()
                let isPackage = isDir && packageExtensions.contains(rawExt)

                let fullPath = dirPath == "/" ? "/\(name)" : "\(dirPath)/\(name)"
                let itemURL = URL(fileURLWithPath: fullPath, isDirectory: isDir && !isPackage)

                let effectiveSize = max(logicalSize, allocSize)
                if !isDir {
                    totalBytes += effectiveSize
                }

                let modDate = Date(timeIntervalSince1970: TimeInterval(modTimeSec))
                let crDate = Date(timeIntervalSince1970: TimeInterval(crTimeSec))
                let classification = FileItem.classify(name: name, isDirectory: isDir, isPackage: isPackage)

                let formattedSize: String
                if isDir && !isPackage {
                    formattedSize = "--"
                } else {
                    formattedSize = Self.fastFormatBytes(effectiveSize)
                }

                let formattedMod = Self.fastFormatDate(modDate, now: now, calendar: cal)
                let formattedCr = Self.fastFormatDate(crDate, now: now, calendar: cal)

                // Avoid 100k xattr syscalls in huge directories; read tags directly for normal folders (<2,000 items)
                let tags = (!isDataless && allItems.count < 2000) ? Self.readFinderTags(atPath: fullPath) : []

                let item = FileItem(
                    id: fullPath,
                    url: itemURL,
                    name: name,
                    lowercasedName: name.lowercased(),
                    ext: classification.ext,
                    displayExt: classification.displayExt,
                    isDirectory: isDir,
                    isPackage: isPackage,
                    isSymbolicLink: isSymlink,
                    isHidden: isHidden,
                    isDataless: isDataless,
                    inode: fileId,
                    size: effectiveSize,
                    modificationDate: modDate,
                    creationDate: crDate,
                    kindCategory: classification.category,
                    kindDescription: classification.description,
                    badgeTintHex: classification.tintHex,
                    tags: tags,
                    childItemCount: dirEntryCount.map { Int($0) },
                    formattedSize: formattedSize,
                    formattedModDate: formattedMod,
                    formattedCreationDate: formattedCr
                )

                allItems.append(item)

                // Render the first 200 items immediately (<16ms) before full sorting completes
                if !didEmitFastBatch && allItems.count == 200 {
                    didEmitFastBatch = true
                    let initialSorted = Self.sortItems(allItems, by: sortField, ascending: ascending)
                    yield(DirectoryLoadBatch(
                        items: initialSorted,
                        isInitialFastBatch: true,
                        isComplete: false,
                        totalBytes: totalBytes
                    ))
                }
            }
        }

        guard !isCancelled() else {
            finish()
            return
        }

        let finalSorted = Self.sortItems(allItems, by: sortField, ascending: ascending)
        yield(DirectoryLoadBatch(
            items: finalSorted,
            isInitialFastBatch: false,
            isComplete: true,
            totalBytes: totalBytes
        ))
        finish()
    }

    static func sortItems(_ items: [FileItem], by field: SortField, ascending: Bool) -> [FileItem] {
        items.sorted { a, b in
            if field == .name && a.isFolderLike != b.isFolderLike {
                return a.isFolderLike
            }
            let result: Bool
            switch field {
            case .name:
                result = fastNaturalLessThan(a.name, b.name)
            case .kind:
                if a.kindCategory != b.kindCategory {
                    result = a.kindCategory < b.kindCategory
                } else {
                    result = fastNaturalLessThan(a.name, b.name)
                }
            case .modified:
                if a.modificationDate != b.modificationDate {
                    result = a.modificationDate > b.modificationDate
                } else {
                    result = fastNaturalLessThan(a.name, b.name)
                }
            case .size:
                if a.size != b.size {
                    result = a.size > b.size
                } else {
                    result = fastNaturalLessThan(a.name, b.name)
                }
            }
            return ascending ? result : !result
        }
    }

    /// Zero-allocation natural sort key comparison for UTF-8 strings (matches Finder numeric ordering: file2 < file10).
    @inline(__always)
    static func fastNaturalLessThan(_ lhs: String, _ rhs: String) -> Bool {
        var lhsCopy = lhs
        var rhsCopy = rhs
        return lhsCopy.withUTF8 { lBuf in
            rhsCopy.withUTF8 { rBuf in
                let lCount = lBuf.count
                let rCount = rBuf.count
                var i = 0
                var j = 0

                while i < lCount && j < rCount {
                    let b1 = lBuf[i]
                    let b2 = rBuf[j]

                    // Check for non-ASCII; fall back to localizedStandardCompare
                    if b1 >= 128 || b2 >= 128 {
                        return lhs.localizedStandardCompare(rhs) == .orderedAscending
                    }

                    let isDigit1 = (b1 >= 48 && b1 <= 57)
                    let isDigit2 = (b2 >= 48 && b2 <= 57)

                    if isDigit1 && isDigit2 {
                        var n1: UInt64 = 0
                        while i < lCount && lBuf[i] >= 48 && lBuf[i] <= 57 {
                            n1 = n1 &* 10 &+ UInt64(lBuf[i] - 48)
                            i += 1
                        }
                        var n2: UInt64 = 0
                        while j < rCount && rBuf[j] >= 48 && rBuf[j] <= 57 {
                            n2 = n2 &* 10 &+ UInt64(rBuf[j] - 48)
                            j += 1
                        }
                        if n1 != n2 {
                            return n1 < n2
                        }
                        continue
                    }

                    // Case-insensitive ASCII compare
                    let c1 = (b1 >= 65 && b1 <= 90) ? (b1 + 32) : b1
                    let c2 = (b2 >= 65 && b2 <= 90) ? (b2 + 32) : b2
                    if c1 != c2 {
                        return c1 < c2
                    }
                    i += 1
                    j += 1
                }
                if lCount != rCount {
                    return lCount < rCount
                }
                return lhs < rhs
            }
        }
    }

    static func fastFormatBytes(_ bytes: Int64) -> String {
        if bytes < 1000 {
            return "\(bytes) B"
        }
        let kb = Double(bytes) / 1000.0
        if kb < 1000 {
            return kb >= 100 ? String(format: "%.0f KB", kb) : String(format: "%.1f KB", kb)
        }
        let mb = kb / 1000.0
        if mb < 1000 {
            return mb >= 100 ? String(format: "%.0f MB", mb) : String(format: "%.1f MB", mb)
        }
        let gb = mb / 1000.0
        if gb < 1000 {
            return gb >= 100 ? String(format: "%.0f GB", gb) : String(format: "%.2f GB", gb)
        }
        let tb = gb / 1000.0
        return String(format: "%.2f TB", tb)
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func fastFormatDate(_ date: Date, now: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let nowComps = calendar.dateComponents([.year, .month, .day], from: now)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0

        if comps.year == nowComps.year && comps.month == nowComps.month {
            if comps.day == nowComps.day {
                return String(format: "Today, %02d:%02d", h, m)
            } else if let d = comps.day, let nd = nowComps.day, nd - d == 1 {
                return String(format: "Yesterday, %02d:%02d", h, m)
            }
        }
        let day = comps.day ?? 1
        let monthIdx = max(0, min(11, (comps.month ?? 1) - 1))
        let year = comps.year ?? 2026
        return "\(day) \(monthNames[monthIdx]) \(year)"
    }

    static func readFinderTags(atPath path: String) -> [FinderTag] {
        let attrName = "com.apple.metadata:_kMDItemUserTags"
        let size = getxattr(path, attrName, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 && size < 16384 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        let readBytes = getxattr(path, attrName, &buffer, size, 0, XATTR_NOFOLLOW)
        guard readBytes > 0 else { return [] }
        let data = Data(buffer.prefix(readBytes))
        guard let rawTags = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] else {
            return []
        }
        return rawTags.map { entry in
            let parts = entry.split(separator: "\n", maxSplits: 1)
            let tagName = String(parts.first ?? Substring(entry))
            let colorIdx = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            return FinderTag(name: tagName, colorIndex: colorIdx)
        }
    }

    static func writeFinderTags(_ tags: [FinderTag], toPath path: String) {
        let attrName = "com.apple.metadata:_kMDItemUserTags"
        if tags.isEmpty {
            removexattr(path, attrName, XATTR_NOFOLLOW)
            return
        }
        let plistArray = tags.map { "\($0.name)\n\($0.colorIndex)" }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plistArray, format: .binary, options: 0) else {
            return
        }
        data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            _ = setxattr(path, attrName, base, data.count, 0, XATTR_NOFOLLOW)
        }
    }
}
