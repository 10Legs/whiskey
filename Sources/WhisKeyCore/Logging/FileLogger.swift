import Foundation

/// Appends timestamped log entries to ~/Library/Logs/WhisKey/whiskey.log.
/// Thread-safe via a serial dispatch queue.
public final class FileLogger: @unchecked Sendable {

    public static let shared = FileLogger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.whiskey.filelogger")
    private let formatter: DateFormatter

    public init() {
        let logsDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first! // swiftlint:disable:this force_unwrapping
            .appendingPathComponent("Logs/WhisKey")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        fileURL = logsDir.appendingPathComponent("whiskey.log")

        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    public func log(_ level: Level = .info, _ message: String,
                    file: String = #file, line: Int = #line) {
        let ts = formatter.string(from: Date())
        let src = (file as NSString).lastPathComponent
        let entry = "[\(ts)] [\(level.rawValue)] \(src):\(line) — \(message)\n"
        queue.async { [weak self] in
            guard let self else { return }
            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.fileURL)
                }
            }
        }
    }

    public enum Level: String {
        case info  = "INFO "
        case warn  = "WARN "
        case error = "ERROR"
    }

    /// Path to the log file, printed at startup so the user knows where to look.
    public var logFilePath: String { fileURL.path }
}
