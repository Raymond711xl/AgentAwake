import CoreServices
import Foundation

public struct FileSystemActivityBatch: Sendable {
    public let urls: [URL]
    public let requiresFullReconciliation: Bool

    public init(
        urls: [URL],
        requiresFullReconciliation: Bool
    ) {
        self.urls = urls
        self.requiresFullReconciliation = requiresFullReconciliation
    }
}

final class FileSystemEventMonitor: @unchecked Sendable {
    typealias Handler = @Sendable (FileSystemActivityBatch) -> Void
    private static let maximumURLsPerBatch = 256

    private let paths: [String]
    private let latency: TimeInterval
    private let handler: Handler
    private let queue = DispatchQueue(
        label: "com.raymond.agentawake.file-events",
        qos: .utility
    )
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let lock = NSLock()
    private var stream: FSEventStreamRef?

    init(
        urls: [URL],
        latency: TimeInterval = 0.75,
        handler: @escaping Handler
    ) {
        self.paths = Array(
            Set(urls.map { $0.standardizedFileURL.path })
        ).sorted()
        self.latency = latency
        self.handler = handler
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard stream == nil, !paths.isEmpty else {
            return stream != nil
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
        )

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return false
        }

        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return false
        }

        stream = created
        return true
    }

    func stop() {
        lock.lock()
        guard let stream else {
            lock.unlock()
            return
        }
        self.stream = nil
        lock.unlock()

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        if DispatchQueue.getSpecific(key: queueKey) == nil {
            queue.sync {}
        }
        FSEventStreamRelease(stream)
    }

    private static let callback: FSEventStreamCallback = {
        _, info, eventCount, eventPaths, eventFlags, _ in
        guard let info else {
            return
        }

        let monitor = Unmanaged<FileSystemEventMonitor>
            .fromOpaque(info)
            .takeUnretainedValue()
        let values = unsafeBitCast(eventPaths, to: NSArray.self)
        let count = min(Int(eventCount), values.count)
        let deliveredCount = min(count, maximumURLsPerBatch)

        var urls: [URL] = []
        urls.reserveCapacity(deliveredCount)
        var requiresFullReconciliation = count > maximumURLsPerBatch
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagEventIdsWrapped
                | kFSEventStreamEventFlagRootChanged
        )

        for index in 0..<deliveredCount {
            if let path = values[index] as? String {
                urls.append(URL(fileURLWithPath: path))
            }
            if eventFlags[index] & rescanFlags != 0 {
                requiresFullReconciliation = true
            }
        }

        guard !urls.isEmpty || requiresFullReconciliation else {
            return
        }
        monitor.handler(
            FileSystemActivityBatch(
                urls: urls,
                requiresFullReconciliation: requiresFullReconciliation
            )
        )
    }
}
