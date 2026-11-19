import Foundation
import SwiftUI
import AppKit
import CoreServices

extension ScanCoordinator {
    // MARK: - Smart Zero-Lag Background Refresh Engine

    func notifyFileSystemMutation(near url: URL? = nil) {
        guard autoRefreshEnabled else { return }
        if let url {
            let stdMutated = url.standardizedFileURL.path
            let stdRoot = URL(fileURLWithPath: scannedRootPath).standardizedFileURL.path
            if stdRoot == "/" || stdMutated.hasPrefix(stdRoot) || stdRoot.hasPrefix(stdMutated) {
                scheduleSmartBackgroundRefresh(delay: 1.8, force: true)
                return
            }
        }
        scheduleSmartBackgroundRefresh(delay: 2.5, force: false)
    }

    func scheduleSmartBackgroundRefresh(delay: TimeInterval = 3.5, force: Bool = false) {
        guard autoRefreshEnabled else { return }
        debounceWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.autoRefreshEnabled else { return }
                guard !self.isScanning, !self.isBackgroundRefreshing else {
                    self.pendingSmartRefresh = true
                    return
                }
                let elapsed = Date().timeIntervalSince(self.lastCompletedScanTime)
                if !force && elapsed < 15.0 {
                    return
                }
                let rootURL = URL(fileURLWithPath: self.scannedRootPath)
                guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
                self.startScan(at: rootURL, silent: true)
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func startSmartPeriodicMonitor() {
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.autoRefreshEnabled, !self.isScanning, !self.isBackgroundRefreshing else { return }
                let rootURL = URL(fileURLWithPath: self.scannedRootPath)
                let vals = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
                let avail = max(vals?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(vals?.volumeAvailableCapacity ?? 0))

                let byteDelta = abs(avail - self.lastObservedAvailableBytes)
                let age = Date().timeIntervalSince(self.lastCompletedScanTime)

                if self.pendingSmartRefresh || (self.lastObservedAvailableBytes > 0 && byteDelta > 24 * 1024 * 1024 && age > 20) {
                    self.pendingSmartRefresh = false
                    self.lastObservedAvailableBytes = avail
                    self.startScan(at: rootURL, silent: true)
                }
            }
        }
    }

    func setupFSWatcher(for path: String) {
        guard autoRefreshEnabled, !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        if watchedPath == path, fsEventStream != nil { return }
        stopFSWatcher()
        watchedPath = path

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (_, clientCallBackInfo, numEvents, _, eventFlags, _) in
            guard let info = clientCallBackInfo else { return }
            let coordinator = Unmanaged<ScanCoordinator>.fromOpaque(info).takeUnretainedValue()
            var hasMeaningfulChange = false
            let mask: FSEventStreamEventFlags = UInt32(
                kFSEventStreamEventFlagItemCreated |
                kFSEventStreamEventFlagItemRemoved |
                kFSEventStreamEventFlagItemRenamed |
                kFSEventStreamEventFlagItemModified |
                kFSEventStreamEventFlagRootChanged
            )
            for i in 0..<numEvents {
                if (eventFlags[i] & mask) != 0 {
                    hasMeaningfulChange = true
                    break
                }
            }
            if hasMeaningfulChange {
                Task { @MainActor in
                    coordinator.scheduleSmartBackgroundRefresh(delay: 4.0, force: false)
                }
            }
        }

        let pathsToWatch = [path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )

        if let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            3.0,
            flags
        ) {
            fsEventStream = stream
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            FSEventStreamStart(stream)
        }
    }

    func stopFSWatcher() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
        watchedPath = ""
    }
}
