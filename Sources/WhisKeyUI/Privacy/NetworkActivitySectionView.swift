import SwiftUI
import WhisKeyCore

// MARK: - NetworkActivitySectionView

/// Popover panel section showing live egress state.
///
/// Placed below the history content area, above the footer, always visible.
/// Driven by the shared NetworkActivityMonitor observable — same state as the
/// menu bar dot badge.
public struct NetworkActivitySectionView: View {

    private let monitor: NetworkActivityMonitor
    private let onOpenPrivacySettings: () -> Void
    @Binding private var hasPulsedRed: Bool

    /// Tick counter incremented every second to force relative-time label refresh.
    @State private var tickCount: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(
        monitor: NetworkActivityMonitor,
        hasPulsedRed: Binding<Bool>,
        onOpenPrivacySettings: @escaping () -> Void
    ) {
        self.monitor = monitor
        self._hasPulsedRed = hasPulsedRed
        self.onOpenPrivacySettings = onOpenPrivacySettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section header with live dot.
            HStack(spacing: 4) {
                Text("Network Activity")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityValue(monitor.egressState.accessibilityStateLabel)
                Spacer()
                NetworkStatusDotView(state: monitor.egressState, hasPulsed: $hasPulsedRed)
            }

            // Warning label (red state only).
            if monitor.egressState == .unexpected {
                Text("! Unexpected egress detected")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                    .accessibilityLabel("Warning: unexpected network egress detected")
            }

            // Byte counters.
            NetworkByteSummaryView(
                bytesSent: monitor.totalBytesSent,
                bytesReceived: monitor.totalBytesReceived
            )

            // Last egress.
            NetworkLastEgressView(lastEgressAt: monitor.lastEgressAt, tickCount: tickCount)

            // Destinations list.
            NetworkDestinationListView(
                destinations: monitor.recentDestinations,
                egressLog: monitor.egressLog,
                onOpenPrivacySettings: onOpenPrivacySettings
            )

            // Settings link (red state only).
            if monitor.egressState == .unexpected {
                Button("View full log in Settings") {
                    onOpenPrivacySettings()
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .accessibilityLabel("View network egress log in Privacy Settings")
            }

            // Monitoring unavailable notice.
            if monitor.egressState == .unavailable {
                Text("Monitoring unavailable")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(timer) { _ in tickCount += 1 }
    }
}

// MARK: - NetworkByteSummaryView

struct NetworkByteSummaryView: View {
    let bytesSent: Int64
    let bytesReceived: Int64

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Sent")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatBytes(bytesSent))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            }
            HStack {
                Text("Received")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatBytes(bytesReceived))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - NetworkLastEgressView

struct NetworkLastEgressView: View {
    let lastEgressAt: Date?
    let tickCount: Int  // Observed to trigger refresh every second.

    var body: some View {
        HStack {
            Text("Last egress")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(relativeLabel)
                .font(.system(size: 12))
                .foregroundStyle(lastEgressAt == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        }
        // tickCount is read to invalidate the view body every second.
        .id(tickCount)
    }

    private var relativeLabel: String {
        guard let date = lastEgressAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - NetworkDestinationListView

struct NetworkDestinationListView: View {
    let destinations: [String]
    let egressLog: [EgressEvent]
    let onOpenPrivacySettings: () -> Void

    private let maxInline = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if destinations.isEmpty {
                HStack {
                    Text("Destinations")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("None ever")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Destinations")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                ForEach(Array(destinations.prefix(maxInline)), id: \.self) { domain in
                    HStack(spacing: 0) {
                        // 12 pt indent per spec.
                        Spacer().frame(width: 12)
                        Text(annotatedDomain(domain))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                }

                if destinations.count > maxInline {
                    let overflow = destinations.count - maxInline
                    Button("and \(overflow) more — view in Settings") {
                        onOpenPrivacySettings()
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                }
            }
        }
    }

    /// Returns the domain annotated with "(model download)" if a currently in-progress
    /// model download matches, per spec edge case 6.3.
    private func annotatedDomain(_ domain: String) -> String {
        // Find the most recent event for this domain.
        if let event = egressLog.first(where: { $0.destination == domain }),
           event.eventType == .modelDownload {
            return "\(domain) (model download)"
        }
        return domain
    }
}

// MARK: - EgressState extension for accessibility

extension EgressState {
    var accessibilityStateLabel: String {
        switch self {
        case .local:       return "Local only — no egress"
        case .audited:     return "Cloud provider active"
        case .unexpected:  return "Warning — unexpected egress detected"
        case .unavailable: return "Monitoring unavailable"
        }
    }
}
