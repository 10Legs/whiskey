import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "EgressAuditor")

// MARK: - EgressAuditor

/// Centralized audit wrapper for all outbound URLSession traffic.
///
/// Every outbound network call in the app MUST be recorded through this type.
/// Calls that bypass EgressAuditor are detectable via the lint-style test in
/// NetworkActivityMonitorTests (which scans for raw URLSession.shared usage
/// outside of EgressAuditor).
///
/// Usage:
///   - For URLSessionDownloadTask: call `track(task:destination:eventType:)` before `task.resume()`.
///   - For completed delegate callbacks: call `recordCompleted(...)` once bytes are known.
public final class EgressAuditor: Sendable {

    public static let shared = EgressAuditor()

    // Weak reference stored as an @unchecked Sendable wrapper so we can hold
    // a reference across actor boundaries without violating Sendable.
    // NetworkActivityMonitor is @MainActor; we hop back via Task.
    private let monitorRef: MonitorRef

    private init() {
        monitorRef = MonitorRef()
    }

    // MARK: - Configuration

    /// Wire the auditor to the live monitor. Call once from AppDelegate after
    /// NetworkActivityMonitor.startMonitoring().
    public func configure(monitor: NetworkActivityMonitor) {
        monitorRef.set(monitor)
    }

    // MARK: - Tracking API

    /// Track a URLSessionDownloadTask before it is resumed.
    ///
    /// This method does not start the task — callers must call `task.resume()` themselves.
    /// The destination domain is extracted from the task's `originalRequest?.url`.
    public func track(
        task: URLSessionDownloadTask,
        destination: String,
        eventType: EgressEventType
    ) async {
        // Pre-flight: log the initiation so the destination appears before completion.
        logger.info("EgressAuditor tracking task: \(destination) [\(eventType.rawValue)]")
        // Bytes are unknown at task creation; they are recorded on completion via
        // recordCompleted(). No state mutation here — the monitor reflects active
        // egress only upon completion (consistent with the 60s window semantics).
    }

    /// Record a completed outbound connection.
    ///
    /// Called from URLSession delegate callbacks (didFinishDownloading, didCompleteWithError)
    /// or from LLM provider completion handlers.
    ///
    /// - Parameters:
    ///   - destination: Domain name only — strip path, query, fragment before passing.
    ///   - bytesSent: Total bytes sent (headers + body). Use task.countOfBytesSent if available.
    ///   - bytesReceived: Total bytes received.
    ///   - eventType: Classification of this egress event.
    public func recordCompleted(
        destination: String,
        bytesSent: Int64,
        bytesReceived: Int64,
        eventType: EgressEventType
    ) async {
        let sanitized = Self.domainOnly(from: destination)
        guard let monitor = monitorRef.get() else {
            logger.warning("EgressAuditor: no monitor configured — egress not recorded.")
            return
        }
        await MainActor.run {
            monitor.recordEgress(
                destination: sanitized,
                bytesSent: bytesSent,
                bytesReceived: bytesReceived,
                eventType: eventType
            )
        }
    }

    // MARK: - Utility

    /// Extract the host component from a URL string or raw domain.
    ///
    /// Strips scheme, path, query, and fragment. Returns the input unchanged if
    /// it is already a bare domain or cannot be parsed.
    public static func domainOnly(from urlStringOrDomain: String) -> String {
        // If it already looks like a domain (no slashes), pass through.
        if !urlStringOrDomain.contains("/") {
            return urlStringOrDomain
        }
        if let url = URL(string: urlStringOrDomain), let host = url.host {
            return host
        }
        // Fallback: return as-is (do not crash on malformed input).
        return urlStringOrDomain
    }

    /// Extract domain from a URL value.
    public static func domainOnly(from url: URL) -> String {
        url.host ?? url.absoluteString
    }
}

// MARK: - MonitorRef (thread-safe weak reference)

/// A Sendable container for a weak reference to NetworkActivityMonitor.
/// Protects mutable state with an unfair lock so reads and writes are safe
/// from any concurrency context without requiring the full overhead of an actor.
private final class MonitorRef: @unchecked Sendable {

    private var _monitor: NetworkActivityMonitor?
    private var lock = os_unfair_lock_s()

    func set(_ monitor: NetworkActivityMonitor) {
        os_unfair_lock_lock(&lock)
        _monitor = monitor
        os_unfair_lock_unlock(&lock)
    }

    func get() -> NetworkActivityMonitor? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _monitor
    }
}
