import AppKit

/// Finds the picture that is really on the desktop.
///
/// `NSWorkspace.desktopImageURL(for:)` only knows about classic picture wallpapers. For the
/// wallpapers chosen in System Settings on macOS 14 and later (aerials in particular) it returns
/// the stock default picture, so anything sampled from it has nothing to do with what the user
/// sees. The wallpaper agent's own store says what is actually showing, so that is read first.
enum WallpaperLocator {
    static var wallpaperSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper", isDirectory: true)
    }

    /// A still image of the current wallpaper, or nil if none can be found.
    static func currentImageURL(for screen: NSScreen) -> URL? {
        let storeURL = wallpaperSupportDirectory.appendingPathComponent("Store/Index.plist")
        if let data = try? Data(contentsOf: storeURL),
           let url = imageURL(fromStore: data, supportDirectory: wallpaperSupportDirectory),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }

    /// Reads the wallpaper store. Internal so it can be tested with a made-up store.
    static func imageURL(fromStore data: Data, supportDirectory: URL) -> URL? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        // One wallpaper for everything, or else the first per-display entry.
        let displays = (root["Displays"] as? [String: Any])?.values.compactMap { $0 as? [String: Any] } ?? []
        let entries = [root["AllSpacesAndDisplays"] as? [String: Any]].compactMap { $0 } + displays
        for entry in entries {
            // "Linked" when desktop and screen saver share a wallpaper, "Desktop" when they don't.
            guard let slot = (entry["Linked"] ?? entry["Desktop"]) as? [String: Any],
                  let content = slot["Content"] as? [String: Any],
                  let choice = (content["Choices"] as? [[String: Any]])?.first else { continue }

            // A picture file the user picked.
            if let file = (choice["Files"] as? [[String: Any]])?.first,
               let relative = file["relative"] as? String, let url = URL(string: relative), url.isFileURL {
                return url
            }
            // An aerial: a video, with a still thumbnail stored next to it.
            if let configData = choice["Configuration"] as? Data,
               let config = try? PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: Any],
               let assetID = config["assetID"] as? String {
                return supportDirectory.appendingPathComponent("aerials/thumbnails/\(assetID).png")
            }
        }
        return nil
    }
}
