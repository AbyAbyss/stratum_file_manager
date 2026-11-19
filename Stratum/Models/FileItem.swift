import Foundation
import UniformTypeIdentifiers
import AppKit

enum FileKindCategory: Int, CaseIterable, Sendable, Comparable {
    case folder = 0
    case image = 1
    case video = 2
    case audio = 3
    case pdf = 4
    case document = 5
    case spreadsheet = 6
    case presentation = 7
    case code = 8
    case archive = 9
    case app = 10
    case other = 11

    static func < (lhs: FileKindCategory, rhs: FileKindCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

}

struct FinderTag: Hashable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let colorIndex: Int // Finder label color index (0..7)

    var hexColor: String {
        switch name.lowercased() {
        case "urgent", "red": return "#FF6B6B"
        case "client", "orange", "yellow": return "#FFC46B"
        case "draft", "blue": return "#4C9DFF"
        case "final", "ship", "green": return "#5FD38D"
        case "review", "purple": return "#B98EFF"
        case "archive", "gray", "grey": return "#938EA8"
        default:
            switch colorIndex {
            case 6: return "#FF6B6B" // Red
            case 7: return "#FFC46B" // Orange
            case 5: return "#FFE066" // Yellow
            case 2: return "#5FD38D" // Green
            case 4: return "#4C9DFF" // Blue
            case 3: return "#B98EFF" // Purple
            case 1: return "#938EA8" // Gray
            default: return "#4C9DFF"
            }
        }
    }

    @MainActor
    var menuDotImage: NSImage {
        let size = NSSize(width: 10, height: 10)
        let img = NSImage(size: size, flipped: false) { rect in
            let color = NSColor(hex: self.hexColor) ?? .systemBlue
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }

    static let presets: [FinderTag] = [
        FinderTag(name: "Urgent", colorIndex: 6),
        FinderTag(name: "Client", colorIndex: 7),
        FinderTag(name: "Draft", colorIndex: 4),
        FinderTag(name: "Final", colorIndex: 2),
        FinderTag(name: "Review", colorIndex: 3),
        FinderTag(name: "Archive", colorIndex: 1),
    ]
}

struct FileItem: Identifiable, Hashable, Sendable {
    let id: String              // Full POSIX path
    let url: URL
    let name: String
    let lowercasedName: String
    let ext: String             // Lowercased extension
    let displayExt: String      // Uppercased short extension for paper badge
    let isDirectory: Bool       // True for non-package folders
    let isPackage: Bool         // True for .app, .photoslibrary, etc.
    let isSymbolicLink: Bool
    let isHidden: Bool
    let isDataless: Bool        // True when SF_DATALESS flag is set (cloud stub)
    let inode: UInt64
    let size: Int64
    let modificationDate: Date
    let creationDate: Date
    let kindCategory: FileKindCategory
    let kindDescription: String
    let badgeTintHex: String
    var tags: [FinderTag]
    var childItemCount: Int?
    let formattedSize: String
    let formattedModDate: String
    let formattedCreationDate: String

    var isFolderLike: Bool {
        isDirectory && !isPackage
    }

    var isAppOrPackage: Bool {
        isPackage || kindCategory == .app || ["app", "prefpane", "pkg", "dmg", "xcodeproj", "xcworkspace", "playground"].contains(ext)
    }

    var isImageOrVideo: Bool {
        kindCategory == .image || kindCategory == .video
    }

    var isVideo: Bool {
        kindCategory == .video
    }

    var isTextPreviewable: Bool {
        guard !isFolderLike && !isPackage else { return false }
        let textExts: Set<String> = [
            "swift", "py", "js", "ts", "tsx", "jsx", "rs", "go", "c", "cpp", "h", "hpp", "m",
            "html", "css", "scss", "json", "yml", "yaml", "toml", "xml", "plist", "sh", "zsh",
            "bash", "sql", "md", "markdown", "txt", "csv", "log", "env", "gitignore", "dockerfile"
        ]
        return textExts.contains(ext) || name.lowercased() == "dockerfile" || name.lowercased() == "makefile"
    }

    var subtitleText: String {
        if isFolderLike {
            if let count = childItemCount {
                return "\(count) \(count == 1 ? "item" : "items")"
            }
            return "Folder"
        }
        if isPackage && size == 0 {
            return kindDescription
        }
        return formattedSize
    }

    static func classify(name: String, isDirectory: Bool, isPackage: Bool) -> (ext: String, displayExt: String, category: FileKindCategory, description: String, tintHex: String) {
        let nsName = name as NSString
        let rawExt = nsName.pathExtension.lowercased()
        let displayExt = rawExt.isEmpty ? "FILE" : String(rawExt.uppercased().prefix(4))

        if isPackage || rawExt == "app" || rawExt == "prefpane" {
            switch rawExt {
            case "app":
                return (rawExt, "APP", .app, "Application", "#2F6BFF")
            case "prefpane":
                return (rawExt, "PREF", .app, "Preference Pane", "#56708F")
            case "photoslibrary":
                return (rawExt, "LIB", .image, "Photos Library", "#D6336C")
            case "key":
                return (rawExt, "KEY", .presentation, "Keynote presentation", "#1D5FC4")
            case "pages":
                return (rawExt, "PGS", .document, "Pages document", "#C2570A")
            case "numbers":
                return (rawExt, "NUM", .spreadsheet, "Numbers spreadsheet", "#1A7F4B")
            default:
                return (rawExt, displayExt, .app, "Package", "#56708F")
            }
        }

        if isDirectory {
            return ("", "", .folder, "Folder", "#6E6A80")
        }

        switch rawExt {
        case "pdf":
            return (rawExt, "PDF", .pdf, "PDF document", "#C62A2F")
        case "svg", "ai", "eps":
            return (rawExt, displayExt, .document, "\(displayExt) vector image", "#A85A00")
        case "jpg", "jpeg":
            return (rawExt, "JPG", .image, "JPEG image", "#0A84C6")
        case "png":
            return (rawExt, "PNG", .image, "PNG image", "#0E8F8A")
        case "heic", "heif", "webp", "gif", "tiff", "tif", "bmp", "raw", "cr2", "cr3", "nef", "arw", "dng", "psd":
            return (rawExt, displayExt, .image, "\(displayExt) image", "#0E8F8A")
        case "mov":
            return (rawExt, "MOV", .video, "QuickTime movie", "#6B3CC9")
        case "mp4", "m4v", "mkv", "webm", "avi", "prores":
            return (rawExt, displayExt, .video, "\(displayExt) video", "#6B3CC9")
        case "wav", "mp3", "m4a", "aac", "flac", "aif", "aiff", "ogg":
            return (rawExt, displayExt, .audio, "\(displayExt) audio", "#6B3CC9")
        case "key", "pptx", "ppt":
            return (rawExt, displayExt, .presentation, rawExt == "key" ? "Keynote presentation" : "Presentation", "#1D5FC4")
        case "xlsx", "xls", "csv", "tsv", "numbers":
            return (rawExt, rawExt == "xlsx" ? "XLS" : displayExt, .spreadsheet, rawExt == "csv" ? "CSV table" : "Excel workbook", "#1A7F4B")
        case "md", "markdown":
            return (rawExt, "MD", .document, "Markdown document", "#4A4760")
        case "txt", "rtf", "doc", "docx", "pages":
            return (rawExt, displayExt, .document, "\(displayExt) document", "#3D5A80")
        case "swift", "py", "js", "ts", "tsx", "jsx", "rs", "go", "c", "cpp", "h", "m", "html", "css", "json", "yml", "yaml", "toml", "sh", "zsh", "sql":
            return (rawExt, displayExt, .code, "\(displayExt) source", "#4A4760")
        case "zip", "tar", "gz", "tgz", "7z", "rar", "dmg", "pkg", "iso":
            return (rawExt, displayExt, .archive, "\(displayExt) archive", "#8A5A3C")
        default:
            return (rawExt, displayExt, .other, rawExt.isEmpty ? "Document" : "\(rawExt.uppercased()) file", "#4A4760")
        }
    }
}
