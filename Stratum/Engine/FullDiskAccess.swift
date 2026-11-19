import Foundation
import AppKit

enum FullDiskAccess {
    private static let hasPromptedKey = "stratum.hasShownFDAPrompt"

    static var hasShownFirstRunPrompt: Bool {
        get { UserDefaults.standard.bool(forKey: hasPromptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasPromptedKey) }
    }

    /// Checks whether the app currently has Full Disk Access by probing TCC-protected directories off the main thread.
    static func checkAccess(completion: @escaping @MainActor (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let probePaths = [
                "\(home)/Library/Safari",
                "\(home)/Library/Mail",
                "\(home)/Library/Messages",
                "/Library/Application Support/com.apple.TCC"
            ]
            var granted = false
            for path in probePaths {
                let fd = Darwin.open(path, O_RDONLY | O_DIRECTORY)
                if fd >= 0 {
                    Darwin.close(fd)
                    granted = true
                    break
                } else if errno == ENOENT {
                    // Directory doesn't exist on this user account; try next
                    continue
                } else if errno == EPERM || errno == EACCES {
                    granted = false
                    break
                }
            }
            Task { @MainActor in
                completion(granted)
            }
        }
    }

    @MainActor
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
