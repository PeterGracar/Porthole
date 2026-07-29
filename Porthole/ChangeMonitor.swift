import Foundation
import CoreServices

/// Watches the MacPorts registry and ports tree with FSEvents and fires a
/// debounced callback once the disk goes quiet — so the app notices installs,
/// uninstalls, and tree syncs made outside Porthole (e.g. `sudo port install`
/// in a terminal). FSEvents rather than kqueue because the interesting writes
/// happen deep inside these directories (registry journal files, synced
/// Portfiles), not at their top level.
final class MacPortsChangeMonitor {
    /// Registry catches install/uninstall/activate; sources catches
    /// selfupdate/sync. Deliberately not the build or distfiles directories —
    /// those churn constantly during a compile without changing anything the
    /// app displays.
    private let watchedPaths = [
        "/opt/local/var/macports/registry",
        "/opt/local/var/macports/sources",
    ]
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?

    /// `onChange` is delivered on the main queue.
    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        let paths = watchedPaths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<MacPortsChangeMonitor>.fromOpaque(info).takeUnretainedValue().noteChange()
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Coalesces event bursts (a tree sync touches thousands of files) into a
    /// single callback 1.5 s after the last event.
    private func noteChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    deinit { stop() }
}
