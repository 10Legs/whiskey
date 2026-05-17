import SwiftUI
import WhisKeyCore

private let phosphorGreen = Color(red: 0, green: 1, blue: 0.533)
private let hudBackground  = Color(red: 0.024, green: 0.031, blue: 0.031)

// MARK: - PrivacySettingsView

/// Settings → Privacy tab: full egress audit log, summary stats, and CSV export.
///
/// All values update live at 1-second intervals via a timer.
/// The CSV export writes to ~/Downloads/ with no save panel (per spec).
public struct PrivacySettingsView: View {

    private let monitor: NetworkActivityMonitor
    @Binding private var hasPulsedRed: Bool

    @State private var tickCount: Int = 0
    @State private var exportConfirmationVisible: Bool = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(monitor: NetworkActivityMonitor, hasPulsedRed: Binding<Bool>) {
        self.monitor = monitor
        self._hasPulsedRed = hasPulsedRed
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: Explanation copy
                Text(
                    "WhisKey logs outbound network connections made since launch. " +
                    "Domain names only — no URLs or content are ever recorded."
                )
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                // MARK: Summary section
                PrivacySummaryView(monitor: monitor, tickCount: tickCount)

                // MARK: Egress log
                HStack(alignment: .firstTextBaseline) {
                    Text("Egress Log (last 100 events)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    exportButton
                }

                Divider()

                EgressLogTableView(log: monitor.egressLog)

                Divider()

                // MARK: Zero-egress claim indicator
                ZeroEgressClaimView(
                    monitor: monitor,
                    tickCount: tickCount
                )
            }
            .padding()
        }
        .background(hudBackground)
        .onReceive(timer) { _ in tickCount += 1 }
    }

    // MARK: - Export Button

    private var exportButton: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button("Export CSV") {
                exportCSV()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Export network activity log as CSV file")

            if exportConfirmationVisible {
                Text("Exported to Downloads")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.green)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
    }

    // MARK: - CSV Export

    private func exportCSV() {
        let header = "timestamp_iso8601,destination,bytes_sent,bytes_received,event_type\n"
        let iso = ISO8601DateFormatter()
        let rows = monitor.egressLog.map { event in
            "\(iso.string(from: event.timestamp))," +
            "\(event.destination)," +
            "\(event.bytesSent)," +
            "\(event.bytesReceived)," +
            "\(event.eventType.rawValue)"
        }.joined(separator: "\n")

        let csv = header + rows

        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)
            .first

        guard let downloadsDir = downloads else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "WhisKey-egress-log-\(timestamp).csv"
        let fileURL = downloadsDir.appendingPathComponent(filename)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            showExportConfirmation()
        } catch {
            // Silently fail — no crash on export error.
        }
    }

    private func showExportConfirmation() {
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) {
            exportConfirmationVisible = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                exportConfirmationVisible = false
            }
        }
    }
}

// MARK: - PrivacySummaryView

struct PrivacySummaryView: View {
    let monitor: NetworkActivityMonitor
    let tickCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summary")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            summaryRow("Total sent", value: formatBytes(monitor.totalBytesSent))
            summaryRow("Total received", value: formatBytes(monitor.totalBytesReceived))
            summaryRow("Connections", value: "\(monitor.egressLog.count)")
            summaryRow("Monitoring since", value: formatMonitoringSince(monitor.monitoringSince))
        }
        .id(tickCount)
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatMonitoringSince(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return "Today at \(f.string(from: date))"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }
}

// MARK: - EgressLogTableView

struct EgressLogTableView: View {
    let log: [EgressEvent]

    var body: some View {
        if log.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No network connections have been made")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            // Column header.
            HStack {
                Text("Timestamp")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 140, alignment: .leading)
                Text("Destination")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Bytes sent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                Text("Type")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
            }

            Divider()

            LazyVStack(spacing: 0) {
                ForEach(log) { event in
                    EgressLogRowView(event: event)
                    Divider().opacity(0.3)
                }
            }
        }
    }
}

// MARK: - EgressLogRowView

struct EgressLogRowView: View {
    let event: EgressEvent

    var body: some View {
        HStack {
            Text(formatTimestamp(event.timestamp))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(event.destination)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatBytes(event.bytesSent))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .trailing)
            Text(eventTypeLabel(event.eventType))
                .font(.system(size: 11))
                .foregroundStyle(event.eventType == .unexpected ? Color.red : Color.secondary)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return "Today \(f.string(from: date))"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func eventTypeLabel(_ type: EgressEventType) -> String {
        switch type {
        case .modelDownload: return "Model download"
        case .cloudLLM:      return "LLM request"
        case .unexpected:    return "Unexpected"
        }
    }
}

// MARK: - ZeroEgressClaimView

struct ZeroEgressClaimView: View {
    let monitor: NetworkActivityMonitor
    let tickCount: Int

    private var isVerified: Bool {
        monitor.egressLog.isEmpty && monitor.egressState == .local
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isVerified ? "checkmark.seal.fill" : "info.circle")
                .foregroundStyle(isVerified ? Color.green : Color.secondary)
            Text("Zero-egress claim: \(isVerified ? "VERIFIED" : "UNVERIFIED")")
                .font(.system(size: 12))
                .foregroundStyle(isVerified ? Color.green : Color.secondary)
            Spacer()
            Text("Last checked: \(lastCheckedLabel)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .id(tickCount)
    }

    private var lastCheckedLabel: String {
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(now) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return "Today at \(f.string(from: now))"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: now)
    }
}
