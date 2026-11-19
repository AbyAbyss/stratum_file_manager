import SwiftUI

/// What a window opens with. Also the identity SwiftUI uses to keep a window's state when it is restored.
struct WindowSeed: Codable, Hashable {
    var id = UUID()
    var path: String?
}

/// Every window has its own `AppState` (tabs, folder, selection), so windows browse independently.
/// What they all share is the single `ScanCoordinator`: one disk scan feeds every window's Storage
/// map and Groups, so opening more windows never scans anything again.
@MainActor
@Observable
final class WindowRegistry {
    static let shared = WindowRegistry()

    /// The window the user is working in. App menu commands act on this one.
    private(set) var active: AppState

    @ObservationIgnored private var states: [UUID: AppState] = [:]

    private init() {
        active = AppState(isPrimary: true)   // claimed by the first window
        firstUnclaimed = active
    }

    @ObservationIgnored private var firstUnclaimed: AppState?

    /// The state for a window, created on first request (so it is safe to call from a view body).
    func state(for seed: WindowSeed) -> AppState {
        if let existing = states[seed.id] { return existing }
        let state: AppState
        if let first = firstUnclaimed {
            state = first
            firstUnclaimed = nil
            if let path = seed.path { state.openFromOutside(URL(fileURLWithPath: path)) }
        } else {
            state = AppState(startURL: seed.path.map { URL(fileURLWithPath: $0, isDirectory: true) }, isPrimary: false)
        }
        states[seed.id] = state
        return state
    }

    func activate(_ state: AppState) {
        guard active !== state else { return }
        active = state
        StratumAppDelegate.shared?.flushPending()
    }

    func remove(_ seed: WindowSeed) {
        guard let gone = states.removeValue(forKey: seed.id) else { return }
        if active === gone, let next = states.values.first { active = next }
    }

    var windowCount: Int { states.count }
}
