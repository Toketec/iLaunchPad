import CoreServices
import Foundation

@MainActor
final class ApplicationDirectoryMonitor {
    private var stream: FSEventStreamRef?
    private var pending: Task<Void, Never>?
    private let onChange: @MainActor () -> Void

    init(roots: [URL], onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            // This stream is scheduled exclusively on the main queue.
            MainActor.assumeIsolated {
                Unmanaged<ApplicationDirectoryMonitor>.fromOpaque(info).takeUnretainedValue().scheduleRefresh()
            }
        }, &context, roots.map(\.path) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            if !FSEventStreamStart(stream) {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        }
    }

    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
                self?.onChange()
                // A bundle can be created before its Info.plist/executable arrives.
                try await Task.sleep(for: .seconds(5))
                self?.onChange()
            } catch { /* A newer directory event supersedes this request. */ }
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
