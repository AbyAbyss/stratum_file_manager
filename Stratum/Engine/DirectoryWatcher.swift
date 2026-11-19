import Foundation
import CoreServices

final class DirectoryWatcher {
    private var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "app.stratum.fsevents-watcher", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval
    private let onCoalescedChange: @Sendable () -> Void
    private(set) var watchedPath: String?

    init(debounceInterval: TimeInterval = 0.150, onCoalescedChange: @escaping @Sendable () -> Void) {
        self.debounceInterval = debounceInterval
        self.onCoalescedChange = onCoalescedChange
    }

    deinit {
        stop()
    }

    func watch(url: URL) {
        let path = url.path
        if watchedPath == path && streamRef != nil {
            return
        }
        stop()
        watchedPath = path

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagFileEvents
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleDebouncedCallback()
        }

        // Latency 0.05s at kernel level + 0.15s debounce coalescing window
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags
        ) else {
            return
        }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func scheduleDebouncedCallback() {
        debounceWorkItem?.cancel()
        let callback = onCoalescedChange
        let work = DispatchWorkItem {
            callback()
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
        watchedPath = nil
    }
}
