import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

final class IconPipeline {
    static let shared = IconPipeline()

    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let appBundleIconCache = NSCache<NSString, NSImage>()
    private var utTypeIconCache: [String: NSImage] = [:]
    private let cacheLock = NSLock()
    private let generator = QLThumbnailGenerator.shared

    private init() {
        thumbnailCache.countLimit = 1500
        thumbnailCache.totalCostLimit = 120 * 1024 * 1024 // 120 MB
        appBundleIconCache.countLimit = 600
    }

    /// Returns the real per-file macOS icon for `.app` bundles, `.prefPane`, packages, etc., or fast UTType icon for regular files.
    func icon(for item: FileItem) -> NSImage {
        if item.isAppOrPackage {
            let key = item.id as NSString
            if let cached = appBundleIconCache.object(forKey: key) {
                return cached
            }
            let workspaceIcon = NSWorkspace.shared.icon(forFile: item.id)
            workspaceIcon.size = NSSize(width: 128, height: 128)
            appBundleIconCache.setObject(workspaceIcon, forKey: key)
            return workspaceIcon
        }
        return fastTypeIcon(
            forExtension: item.ext,
            isDirectory: item.isDirectory,
            isPackage: item.isPackage,
            path: item.id
        )
    }

    /// Tier 1 (synchronous, 0ms): Returns a cached thumbnail if already loaded, or a cached UTType icon by extension.
    func cachedThumbnail(for path: String, size: CGSize) -> NSImage? {
        let key = "\(path)#\(Int(size.width))x\(Int(size.height))" as NSString
        return thumbnailCache.object(forKey: key)
    }

    func fastTypeIcon(forExtension ext: String, isDirectory: Bool, isPackage: Bool, path: String? = nil) -> NSImage {
        let lowerExt = ext.lowercased()
        if let path, (isPackage || lowerExt == "app" || lowerExt == "prefpane") {
            let key = path as NSString
            if let cached = appBundleIconCache.object(forKey: key) {
                return cached
            }
            let workspaceIcon = NSWorkspace.shared.icon(forFile: path)
            workspaceIcon.size = NSSize(width: 128, height: 128)
            appBundleIconCache.setObject(workspaceIcon, forKey: key)
            return workspaceIcon
        }

        let cacheKey = isDirectory && !isPackage ? "__FOLDER__" : (lowerExt.isEmpty ? "__FILE__" : lowerExt)
        cacheLock.lock()
        if let hit = utTypeIconCache[cacheKey] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let icon: NSImage
        if isDirectory && !isPackage {
            icon = NSWorkspace.shared.icon(for: .folder)
        } else if let utType = UTType(filenameExtension: lowerExt), !lowerExt.isEmpty {
            icon = NSWorkspace.shared.icon(for: utType)
        } else {
            icon = NSWorkspace.shared.icon(for: .data)
        }

        cacheLock.lock()
        utTypeIconCache[cacheKey] = icon
        cacheLock.unlock()
        return icon
    }

    /// Tier 2 (async, cancellable): Enqueues a QLThumbnailGenerator request tied to cell reuse lifecycle.
    /// Never requests thumbnails for dataless cloud stubs (`isDataless == true`).
    @discardableResult
    func requestThumbnail(
        for item: FileItem,
        size: CGSize,
        scale: CGFloat = 2.0,
        completion: @escaping @MainActor (NSImage?) -> Void
    ) -> QLThumbnailGenerator.Request? {
        guard !item.isDataless, !item.isFolderLike else {
            return nil
        }

        let key = "\(item.id)#\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            Task { @MainActor in
                completion(cached)
            }
            return nil
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        request.iconMode = false

        generator.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let cgImage = representation?.cgImage else {
                Task { @MainActor in
                    completion(nil)
                }
                return
            }
            let nsImage = NSImage(cgImage: cgImage, size: size)
            let cost = cgImage.bytesPerRow * cgImage.height
            self?.thumbnailCache.setObject(nsImage, forKey: key, cost: cost)
            Task { @MainActor in
                completion(nsImage)
            }
        }
        return request
    }

    func cancelRequest(_ request: QLThumbnailGenerator.Request?) {
        guard let request else { return }
        generator.cancel(request)
    }
}
