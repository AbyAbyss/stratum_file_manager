import Foundation

/// The app's version and its public links, in one place.
enum AppInfo {
    /// `MARKETING_VERSION` from project.yml, so Settings, the release and the tag always agree.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static let authorName = "Aby Saji"
    static let author = URL(string: "https://abyabyss.github.io/")!
    static let repository = URL(string: "https://github.com/AbyAbyss/stratum_file_manager")!
    static let releases = URL(string: "https://github.com/AbyAbyss/stratum_file_manager/releases")!
    static let newIssue = URL(string: "https://github.com/AbyAbyss/stratum_file_manager/issues/new")!
    /// Buy Me a Coffee page (the same handle as Yankit).
    static let support = URL(string: "https://buymeacoffee.com/abyabyss")!
}
