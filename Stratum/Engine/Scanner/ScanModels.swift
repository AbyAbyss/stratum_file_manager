import Foundation

enum FileTypeCategory: Int, CaseIterable, Sendable, Identifiable {
    case video = 0
    case photos = 1
    case code = 2
    case apps = 3
    case documents = 4
    case music = 5
    case archives = 6
    case other = 7

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .video: return "Video"
        case .photos: return "Photos"
        case .code: return "Code"
        case .apps: return "Apps"
        case .documents: return "Documents"
        case .music: return "Music"
        case .archives: return "Archives"
        case .other: return "Other"
        }
    }

    var tintHex: String {
        switch self {
        case .video: return "#7C5CFF"
        case .photos: return "#4AD6C8"
        case .code: return "#5FD38D"
        case .apps: return "#5AA9FF"
        case .documents: return "#FFC46B"
        case .music: return "#FF7A90"
        case .archives: return "#B784F7"
        case .other: return "#8B86A3"
        }
    }
}

struct DirRow: Identifiable, Hashable, Sendable {
    let id: Int64
    let parentId: Int64?
    let name: String
    let depth: Int
    let isHidden: Bool
    let isPackage: Bool
    let mtime: Date?
    let totalSize: Int64
    let descendantFileCount: Int64

    /// A copy with `bytes` removed from the total, used to keep ancestors' sizes right
    /// after something inside them is trashed.
    func removingBytes(_ bytes: Int64) -> DirRow {
        DirRow(
            id: id, parentId: parentId, name: name, depth: depth, isHidden: isHidden,
            isPackage: isPackage, mtime: mtime, totalSize: max(0, totalSize - bytes),
            descendantFileCount: descendantFileCount
        )
    }
}

struct GroupRow: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let tagline: String
    let count: Int
    let total: Int64
    let avgAgeDays: Double
    let devOnly: Bool
}

struct GroupInstanceRow: Identifiable, Hashable, Sendable {
    var id: Int64 { dirRow.id }
    let dirRow: DirRow
    let fullPath: String
    let parentProjectName: String
}

struct FileTypeTotal: Identifiable, Hashable, Sendable {
    var id: FileTypeCategory { type }
    let type: FileTypeCategory
    let totalSize: Int64
    let fileCount: Int64
}

struct LargeFileRow: Identifiable, Hashable, Sendable {
    let id: Int64
    let dirId: Int64
    let name: String
    let size: Int64
    let mtime: Date?
    let ext: String?
    let type: FileTypeCategory
}

struct ScanProgress: Sendable {
    var fraction: Double
    var filesScanned: Int64
    var currentPath: String
    var etaSeconds: Int?
}

struct VolumeInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let url: URL

    var used: Int64 { max(0, totalCapacity - availableCapacity) }
}

struct DeleteTarget: Identifiable, Hashable, Sendable {
    var id: String { path }
    let dirId: Int64?
    let fileName: String?
    let path: String
    let size: Int64
    let mtime: Date?
    let isProtected: Bool

    var isFile: Bool { fileName != nil }
}

struct DuplicateCluster: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let fileSize: Int64
    let paths: [String]

    var reclaimableBytes: Int64 {
        fileSize * Int64(max(0, paths.count - 1))
    }
}

enum GroupCatalog {
    struct Entry: Sendable {
        let name: String
        let tagline: String
        let devOnly: Bool
        let category: String // "Dev caches", "Design", "Archives", "All"
    }

    static let entries: [Entry] = [
        Entry(name: "node_modules",     tagline: "JavaScript dependencies",     devOnly: true,  category: "Dev caches"),
        Entry(name: "DerivedData",      tagline: "Xcode build cache",           devOnly: true,  category: "Dev caches"),
        Entry(name: "Caches",           tagline: "App caches",                  devOnly: false, category: "Dev caches"),
        Entry(name: ".venv",            tagline: "Python virtual environments", devOnly: true,  category: "Dev caches"),
        Entry(name: "venv",             tagline: "Python virtual environments", devOnly: true,  category: "Dev caches"),
        Entry(name: "__pycache__",      tagline: "Python compiled cache",       devOnly: true,  category: "Dev caches"),
        Entry(name: "target",           tagline: "Rust / Java build output",    devOnly: true,  category: "Dev caches"),
        Entry(name: ".gradle",          tagline: "Gradle build cache",          devOnly: true,  category: "Dev caches"),
        Entry(name: "Pods",             tagline: "CocoaPods dependencies",      devOnly: true,  category: "Dev caches"),
        Entry(name: ".cache",           tagline: "Tool caches",                 devOnly: true,  category: "Dev caches"),
        Entry(name: "Exports",          tagline: "Rendered media & deliverables", devOnly: false, category: "Design"),
        Entry(name: "Renders",          tagline: "Video & 3D render outputs",   devOnly: false, category: "Design"),
        Entry(name: "Archive",          tagline: "Archived project snapshots",  devOnly: false, category: "Archives"),
        Entry(name: "Downloads",        tagline: "Downloaded installers & files", devOnly: false, category: "Archives"),
    ]
}

enum FileTypeClassifier {
    private static let table: [String: FileTypeCategory] = {
        var m: [String: FileTypeCategory] = [:]
        for ext in ["mov","mp4","m4v","avi","mkv","wmv","webm","mpg","mpeg","flv","3gp","hevc","prores","mts","m2ts","ts","vob"] {
            m[ext] = .video
        }
        for ext in ["jpg","jpeg","png","heic","heif","gif","bmp","tiff","tif","raw","cr2","cr3","nef","arw","dng","webp","psd","ai","svg","icns","ico","fig","sketch"] {
            m[ext] = .photos
        }
        for ext in ["swift","m","mm","h","hpp","c","cc","cpp","cxx","java","kt","kts","scala","groovy","js","mjs","cjs","jsx","ts","tsx","vue","svelte","py","pyc","pyo","ipynb","rb","erb","go","rs","php","cs","fs","fsx","html","htm","css","scss","sass","less","json","yaml","yml","toml","xml","plist","graphql","gql","sql","sh","bash","zsh","fish","lua","r","jl","elm","clj","cljs","ex","exs","erl","hrl","dart","nim","zig","v","hs","ml","mli","pl","pm","tcl","md","markdown","rst","tex","lock","gradle","cmake"] {
            m[ext] = .code
        }
        for ext in ["app","dmg","pkg","mpkg","xip","ipa","apk"] {
            m[ext] = .apps
        }
        for ext in ["pdf","doc","docx","odt","rtf","pages","xls","xlsx","ods","numbers","csv","tsv","ppt","pptx","odp","key","txt","epub","mobi","azw","azw3"] {
            m[ext] = .documents
        }
        for ext in ["mp3","aac","m4a","wav","flac","alac","ogg","oga","opus","wma","aif","aiff","mid","midi","ape","dsf"] {
            m[ext] = .music
        }
        for ext in ["zip","tar","gz","tgz","bz2","tbz","xz","txz","zst","lz","rar","7z","sit","sitx","jar","war","ear","iso"] {
            m[ext] = .archives
        }
        return m
    }()

    @inline(__always)
    static func category(forExtension ext: String?) -> FileTypeCategory {
        guard let ext, !ext.isEmpty else { return .other }
        return table[ext] ?? .other
    }
}

struct BoundedMinHeap<T: Comparable>: Sendable where T: Sendable {
    private(set) var items: [T] = []
    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        items.reserveCapacity(capacity + 1)
    }

    var count: Int { items.count }
    var min: T? { items.first }

    mutating func consider(_ item: T) {
        if items.count < capacity {
            items.append(item)
            siftUp(items.count - 1)
        } else if let head = items.first, item > head {
            items[0] = item
            siftDown(0)
        }
    }

    private mutating func siftUp(_ index: Int) {
        var i = index
        while i > 0 {
            let parent = (i - 1) / 2
            if items[i] < items[parent] {
                items.swapAt(i, parent)
                i = parent
            } else { break }
        }
    }

    private mutating func siftDown(_ index: Int) {
        var i = index
        let n = items.count
        while true {
            let l = 2 * i + 1
            let r = 2 * i + 2
            var smallest = i
            if l < n && items[l] < items[smallest] { smallest = l }
            if r < n && items[r] < items[smallest] { smallest = r }
            if smallest == i { break }
            items.swapAt(i, smallest)
            i = smallest
        }
    }
}
