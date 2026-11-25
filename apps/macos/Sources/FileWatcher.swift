import Foundation

/// Watches local quota directories via kernel kqueue (DispatchSource) so
/// updates from `agy` statusLine, Codex session logs, or Open Slot JSON files
/// reflect in the menu bar and popover within ~250ms with zero idle polling.
final class DirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.quotaring.filewatcher", qos: .utility)
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start(directories: [URL]) {
        stop()
        var uniquePaths = Set<String>()
        for url in directories {
            let path = url.standardizedFileURL.path
            guard !uniquePaths.contains(path) else { continue }
            uniquePaths.insert(path)
            watchDirectory(atPath: path)
        }
    }

    func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        for src in sources {
            src.cancel()
        }
        sources.removeAll()
    }

    private func watchDirectory(atPath path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleCallback()
        }

        source.setCancelHandler {
            close(fd)
        }

        sources.append(source)
        source.resume()
    }

    private func scheduleCallback() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange()
            }
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
