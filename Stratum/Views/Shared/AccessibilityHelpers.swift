import SwiftUI

extension View {
    /// Tooltip plus accessibility label, for icon-only controls. A bare `.help` is only exposed
    /// to VoiceOver as a hint, so these buttons were read out as just "button".
    /// Don't use it on controls that already show text; their visible text is their label.
    func stratumHelp(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }
}
