import Foundation

struct ProtectedPathEntry: Identifiable, Hashable, Sendable, Codable {
    let path: String
    let isSystem: Bool
    var id: String { path }
}

enum ProtectedPaths {
    private static let userPathsKey = "stratum.userProtectedPaths"

    /// Compiled-in, non-removable system protected paths.
    static let systemPaths: [String] = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/private",
        "/dev",
        "/cores",
        "~/Library/Keychains",
        "~/.ssh",
        "~/.gnupg",
    ]

    static func all() -> [ProtectedPathEntry] {
        let sys = systemPaths.map { ProtectedPathEntry(path: $0, isSystem: true) }
        let usr = loadUserPaths().map { ProtectedPathEntry(path: $0, isSystem: false) }
        return sys + usr
    }

    static func loadUserPaths() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: userPathsKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    static func saveUserPaths(_ paths: [String]) {
        let data = (try? JSONEncoder().encode(paths)) ?? Data()
        UserDefaults.standard.set(data, forKey: userPathsKey)
    }

    static func resolve(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let std = (expanded as NSString).standardizingPath
        return std.count > 1 && std.hasSuffix("/") ? String(std.dropLast()) : std
    }

    /// True if `candidatePath` is root `/`, or is equal to / inside any protected path.
    static func isProtected(_ candidatePath: String, additional: [String] = []) -> Bool {
        let normalized = resolve(candidatePath)
        if normalized == "/" || normalized == "/Users" || normalized == resolve("~") {
            return true
        }
        let allPaths = systemPaths + loadUserPaths() + additional
        for prot in allPaths {
            let p = resolve(prot)
            if normalized == p { return true }
            if normalized.hasPrefix(p + "/") { return true }
        }
        return false
    }
}
