import Foundation

/// Appends timestamped log entries to ~/Library/Logs/WhisKey/whiskey.log.
/// Thread-safe via a serial dispatch queue.
///
/// Rotation policy:
///   - Maximum log file size: 5 MB
///   - Maximum rotated files retained: 3 (whiskey.log.1 … whiskey.log.3)
///   - Rotation is checked at init and before every write
public final class FileLogger: @unchecked Sendable {

    public static let shared = FileLogger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.whiskey.filelogger")
    private let formatter: DateFormatter

    // MARK: - Rotation constants

    private static let maxFileSizeBytes = 5 * 1024 * 1024   // 5 MB
    private static let maxRotatedFiles  = 3

    public init() {
        let logsDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first! // swiftlint:disable:this force_unwrapping
            .appendingPathComponent("Logs/WhisKey")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        fileURL = logsDir.appendingPathComponent("whiskey.log")

        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Check rotation once at startup (runs synchronously so the file is
        // ready before the first external log call arrives).
        queue.sync { self.rotateIfNeeded() }
    }

    // MARK: - Public API

    public func log(_ level: Level = .info, _ message: String,
                    file: String = #file, line: Int = #line) {
        let ts = formatter.string(from: Date())
        let src = (file as NSString).lastPathComponent
        let entry = "[\(ts)] [\(level.rawValue)] \(src):\(line) — \(message)\n"
        queue.async { [weak self] in
            guard let self else { return }
            self.rotateIfNeeded()
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

    /// Path to the active log file, printed at startup so the user knows where to look.
    public var logFilePath: String { fileURL.path }

    // MARK: - Private rotation

    /// Must be called on `queue` only.
    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard
            let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
            let size  = attrs[.size] as? Int,
            size > Self.maxFileSizeBytes
        else { return }

        let base = fileURL.deletingLastPathComponent()
        let name = fileURL.lastPathComponent  // "whiskey.log"

        // Drop the oldest rotated file to stay within the retention limit.
        try? fm.removeItem(at: base.appendingPathComponent("\(name).\(Self.maxRotatedFiles)"))

        // Shift whiskey.log.2 → whiskey.log.3, whiskey.log.1 → whiskey.log.2
        for index in stride(from: Self.maxRotatedFiles - 1, through: 1, by: -1) {
            let src = base.appendingPathComponent("\(name).\(index)")
            let dst = base.appendingPathComponent("\(name).\(index + 1)")
            try? fm.moveItem(at: src, to: dst)
        }

        // Rotate active log: whiskey.log → whiskey.log.1
        try? fm.moveItem(at: fileURL, to: base.appendingPathComponent("\(name).1"))

        // Create a fresh whiskey.log so the next write succeeds immediately.
        fm.createFile(atPath: fileURL.path, contents: nil)
    }
}
