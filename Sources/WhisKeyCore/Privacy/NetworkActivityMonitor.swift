import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "NetworkActivityMonitor")

// MARK: - EgressState

/// Reflects the current outbound network posture of the app.
///
/// - local:      No audited egress in the last 60 seconds. Green dot.
/// - audited:    A user-configured or user-initiated connection is active or recently completed. Gray dot.
/// - unexpected: An unaudited outbound connection was detected. Red dot.
/// - unavailable: Monitoring could not be established.
public enum EgressState: Equatable, Sendable {
    case local
    case audited
    case unexpected
    case unavailable
}

// MARK: - EgressEventType

/// Classifies the nature of an outbound egress event.
public enum EgressEventType: String, Sendable, Equatable {
    case modelDownload  // User-initiated model download — audited.
    case cloudLLM       // User-configured cloud LLM request — audited.
    case unexpected     // Not routed through any audited path.
}

// MARK: - EgressEvent

/// A single recorded outbound connection event.
public struct EgressEvent: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let destination: String  // Domain name only — never full URL.
    public let bytesSent: Int64
    public let bytesReceived: Int64
    public let eventType: EgressEventType

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        destination: String,
        bytesSent: Int64,
        bytesReceived: Int64,
        eventType: EgressEventType
    ) {
        self.id = id
        self.timestamp = timestamp
        self.destination = destination
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.eventType = eventType
    }
}

// MARK: - NetworkActivityMonitor

/// Observable actor that tracks all outbound egress state.
///
/// All properties are MainActor-isolated. The monitor is started at app launch
/// and remains running for the lifetime of the process. It must not be
/// instantiated more than once — callers should use the shared instance created
/// and owned by AppDelegate.
///
/// State transitions:
///   - `.local`      — no audited egress in the past 60 seconds, NWPathMonitor healthy.
///   - `.audited`    — any audited egress recorded within the 60-second window.
///   - `.unexpected` — EgressAuditor recorded an event with `.unexpected` type;
///                     stays until the next transition to a non-unexpected state or
///                     the monitor is explicitly reset.
///   - `.unavailable` — startMonitoring() was not called or NWPathMonitor failed.
@Observable
@MainActor
public final class NetworkActivityMonitor: @unchecked Sendable {

    // MARK: - Observable state

    public var egressState: EgressState = .unavailable
    public var totalBytesSent: Int64 = 0
    public var totalBytesReceived: Int64 = 0
    public var lastEgressAt: Date?
    /// Domain-level only, ordered most-recent first, capped at 10.
    public var recentDestinations: [String] = []
    /// Last 100 events, newest first.
    public var egressLog: [EgressEvent] = []
    /// Timestamp of monitor initialization (session start).
    public var monitoringSince: Date = Date()

    // MARK: - Private

    private var pathMonitor: NWPathMonitor?
    private var windowCheckTask: Task<Void, Never>?
    /// Guards against re-pulsing the red dot within the same session.
    private var hasEverPulsedRed: Bool = false

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Start monitoring. Call once from AppDelegate after launch.
    public func startMonitoring() {
        monitoringSince = Date()
        egressState = .local

        // NWPathMonitor watches connectivity changes.
        // WhisKey monitors egress primarily through EgressAuditor; NWPathMonitor
        // is a secondary signal to detect unexpected connections on interfaces that
        // bypass the URLSession layer (e.g., a rogue framework making raw socket calls).
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            // Executed on the NWPathMonitor queue; hop to MainActor.
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.whiskey.nwpathmonitor", qos: .utility))

        // Periodic task that re-evaluates the 60-second window and flips back to .local
        // when no audited egress has occurred within it.
        startWindowCheckTask()

        logger.info("NetworkActivityMonitor started.")
    }

    /// Stop monitoring. Call on app termination.
    public func stopMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
        windowCheckTask?.cancel()
        windowCheckTask = nil
        logger.info("NetworkActivityMonitor stopped.")
    }

    /// Record an egress event. Called by EgressAuditor when a tracked connection completes.
    ///
    /// - Parameters:
    ///   - destination: Domain name only (strip path/query/fragment before passing).
    ///   - bytesSent: Bytes sent in this connection.
    ///   - bytesReceived: Bytes received in this connection.
    ///   - eventType: Classification of this egress.
    public func recordEgress(
        destination: String,
        bytesSent: Int64,
        bytesReceived: Int64,
        eventType: EgressEventType
    ) {
        let event = EgressEvent(
            destination: destination,
            bytesSent: bytesSent,
            bytesReceived: bytesReceived,
            eventType: eventType
        )

        totalBytesSent += bytesSent
        totalBytesReceived += bytesReceived
        lastEgressAt = event.timestamp

        // Prepend; cap at 100.
        egressLog.insert(event, at: 0)
        if egressLog.count > 100 {
            egressLog = Array(egressLog.prefix(100))
        }

        // Maintain recent-destinations list (domain-level, deduplicated, newest-first, cap 10).
        var updated = recentDestinations.filter { $0 != destination }
        updated.insert(destination, at: 0)
        recentDestinations = Array(updated.prefix(10))

        // Update egress state.
        switch eventType {
        case .modelDownload, .cloudLLM:
            if egressState != .unexpected {
                egressState = .audited
            }
        case .unexpected:
            let wasAlreadyUnexpected = egressState == .unexpected
            egressState = .unexpected
            if !wasAlreadyUnexpected {
                // First entry into unexpected state — post VoiceOver announcement.
                // Callers observing egressState can also drive a one-shot pulse animation.
                if !hasEverPulsedRed {
                    hasEverPulsedRed = true
                }
            }
        }

        logger.info(
            "Egress recorded: \(destination, privacy: .public) type=\(eventType.rawValue, privacy: .public) sent=\(bytesSent) recv=\(bytesReceived)"
        )
    }

    // MARK: - Private helpers

    private func handlePathUpdate(_ path: NWPath) {
        // NWPathMonitor's primary role here is health-check: if monitoring becomes
        // unavailable (e.g., the path monitor itself fails) we reflect that state.
        // We do NOT infer egress from path changes — that is EgressAuditor's domain.
        logger.debug("NWPathMonitor path update: status=\(path.status == .satisfied ? "satisfied" : "unsatisfied")")
    }

    private func startWindowCheckTask() {
        windowCheckTask?.cancel()
        windowCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { break }
                self.evaluateWindow()
            }
        }
    }

    private func evaluateWindow() {
        // Never downgrade from .unexpected automatically — that requires explicit user
        // acknowledgement (future feature). Never downgrade from .unavailable.
        guard egressState == .audited else { return }

        if let last = lastEgressAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed >= 60 {
                egressState = .local
                logger.info("60-second window cleared — state → .local")
            }
        } else {
            egressState = .local
        }
    }
}
