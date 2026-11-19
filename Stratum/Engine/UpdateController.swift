import Foundation
import Sparkle

/// Checks for and installs new versions with Sparkle.
///
/// Updates are verified with an EdDSA signature, so the updater only starts when the build
/// carries a public key (`SUPublicEDKey` in Info.plist, set from `SPARKLE_PUBLIC_KEY` in
/// project.yml). A build without one, such as a fork or a local build before the key is set up,
/// simply has no updater instead of showing Sparkle's configuration error. See docs/RELEASING.md.
@MainActor
final class UpdateController {
    static let shared = UpdateController()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// Whether this build can update itself.
    let isAvailable: Bool = {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return !(key ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }()

    private init() {}

    /// Starts the updater. Sparkle asks once, on a later launch, whether to check automatically,
    /// and then follows the answer.
    func start() {
        guard isAvailable else { return }
        controller.startUpdater()
    }

    /// Checks now and shows the result, including "you're up to date".
    func checkForUpdates() {
        guard isAvailable else { return }
        controller.checkForUpdates(nil)
    }
}
