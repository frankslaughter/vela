import Foundation
import OSLog

/// Logs to the system log and to a file in the app's Documents folder.
///
/// The file exists because a phone's system log cannot be read from the Mac's command line.
/// Copy it off with:
///
///     xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
///         --domain-identifier com.tower3.vela --source Documents/vela-log.txt --destination vela-log.txt
struct EventLog: Sendable {
    private let category: String
    private let system: Logger

    init(category: String) {
        self.category = category
        system = Logger(subsystem: "com.tower3.vela", category: category)
    }

    func info(_ message: String) {
        system.info("\(message, privacy: .public)")
        LogFile.shared.write(category, message)
    }

    func error(_ message: String) {
        system.error("\(message, privacy: .public)")
        LogFile.shared.write(category, "ERROR " + message)
    }
}

/// The file behind `EventLog`. One file, moved aside once when it passes half a megabyte.
final class LogFile: @unchecked Sendable {
    static let shared = LogFile()

    private let queue = DispatchQueue(label: "com.tower3.vela.log")
    private var handle: FileHandle?
    /// Lines not yet sent to the base station. Test mode drains this; otherwise it just stays short.
    private var pending: [String] = []
    private let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = folder.appendingPathComponent("vela-log.txt")
        let manager = FileManager.default
        if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int, size > 512_000 {
            let old = folder.appendingPathComponent("vela-log-old.txt")
            try? manager.removeItem(at: old)
            try? manager.moveItem(at: url, to: old)
        }
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let day = Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()) // the phone's own date, not Greenwich's
        write("app", "=== Vela \(version) started \(day) ===")
    }

    func write(_ category: String, _ message: String) {
        let now = Date()
        queue.async { [self] in
            let line = "\(time.string(from: now)) [\(category)] \(message)\n"
            try? handle?.write(contentsOf: Data(line.utf8))
            pending.append(line)
            if pending.count > 1500 { pending.removeFirst(pending.count - 1500) }
        }
    }

    /// Hands over the lines written since the last call.
    func takePending() async -> [String] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let lines = pending
                pending = []
                continuation.resume(returning: lines)
            }
        }
    }

    /// Returns lines that could not be sent, to go out with the next batch.
    func putBack(_ lines: [String]) {
        queue.async { [self] in pending = Array((lines + pending).suffix(1500)) }
    }
}
