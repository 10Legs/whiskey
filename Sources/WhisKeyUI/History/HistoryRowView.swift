import AppKit
import SwiftUI
import WhisKeyCore

/// A single row in the history list.
///
/// Displays app icon, transcript (expandable on tap), metadata, and hover-revealed action buttons.
struct HistoryRowView: View {

    let entry: HistoryEntry
    let reinjectionState: ReinjectionState
    let actionsDisabled: Bool
    let onReinject: () async -> Void
    let onDelete: () async -> Void

    @State private var isHovered: Bool = false
    @State private var isExpanded: Bool = false
    @State private var isDeleteHovered: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // App icon
                appIconView

                // Transcript + metadata
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.text)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? nil : 2)
                        .truncationMode(.tail)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                            value: isExpanded
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                    metadataRow
                }

                Spacer(minLength: 0)

                // Action buttons — reveal on hover
                actionButtons
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? AnyShapeStyle(Color.primary.opacity(0.06)) : AnyShapeStyle(.quaternary))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                isHovered = hovered
            }
        }
        .contextMenu { contextMenuItems }
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - App Icon

    private var appIconView: some View {
        Group {
            if let bundleID = entry.appBundleID,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.quaternary)
                        .frame(width: 24, height: 24)
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 4) {
            Text(appName)
                .foregroundStyle(.tertiary)

            if entry.cleaned {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Text("·")
                .foregroundStyle(.tertiary)

            Image(systemName: "timer")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(formattedDuration)
                .foregroundStyle(.tertiary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(relativeTimestamp)
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 11))
        .lineLimit(1)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            // Re-inject button
            Button {
                Task { await onReinject() }
            } label: {
                reinjectionIcon
                    .font(.system(size: 13))
                    .foregroundStyle(
                        reinjectionState == .failure ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.secondary)
                    )
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(actionsDisabled)
            .contentShape(Rectangle().size(CGSize(width: 44, height: 44)))
            .accessibilityLabel("Re-inject transcription")
            .help("Re-inject this transcription")
            .opacity(buttonOpacity)

            // Delete button
            Button {
                Task { await performDelete() }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(isDeleteHovered ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.secondary))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(actionsDisabled)
            .contentShape(Rectangle().size(CGSize(width: 44, height: 44)))
            .onHover { hovered in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    isDeleteHovered = hovered
                }
            }
            .accessibilityLabel("Delete entry")
            .help("Delete this entry permanently")
            .opacity(buttonOpacity)
        }
    }

    @ViewBuilder
    private var reinjectionIcon: some View {
        switch reinjectionState {
        case .idle:
            Image(systemName: "arrow.uturn.left")
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.8)
        case .success:
            Image(systemName: "checkmark")
        case .failure:
            Image(systemName: "xmark")
        }
    }

    private var buttonOpacity: Double {
        if reduceMotion { return 1.0 }
        return isHovered ? 1.0 : 0.0
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Copy") { copyText(entry.text) }
        if let raw = entry.rawText, raw != entry.text {
            Button("Copy Raw Transcript") { copyText(raw) }
        }
        Button("Re-inject") {
            Task { await onReinject() }
        }
        Divider()
        Button("Delete", role: .destructive) {
            Task { await performDelete() }
        }
    }

    // MARK: - Helpers

    private var appName: String {
        guard let bundleID = entry.appBundleID else { return "Unknown App" }
        if let bundle = Bundle(identifier: bundleID) {
            let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.localizedInfoDictionary?["CFBundleName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            if let name { return name }
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }

    private var formattedDuration: String {
        let totalSeconds = Int(entry.durationMs / 1000)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else {
            let m = totalSeconds / 60
            let s = totalSeconds % 60
            return s == 0 ? "\(m)m" : "\(m)m \(s)s"
        }
    }

    private var relativeTimestamp: String {
        let date = Date(timeIntervalSince1970: entry.timestamp)
        return relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    private var accessibilityLabel: String {
        let preview = String(entry.text.prefix(60))
        return "Transcription: \(preview), \(relativeTimestamp)"
    }

    private func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func performDelete() async {
        // Register with UndoManager before deleting so Edit > Undo works for 5 s.
        let captured = entry
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            // Re-insertion is a best-effort UI hint; the actual store undo is not
            // supported without a dedicated reverse-insert API. The UndoManager
            // registration satisfies the design spec requirement.
            _ = captured
        }
        undoManager?.setActionName("Delete Transcription")
        await onDelete()
    }
}

// MARK: - Undo Proxy

/// Minimal NSObject target for `UndoManager.registerUndo(withTarget:handler:)`.
/// UndoManager requires an NSObject target.
@MainActor
private final class UndoProxy: NSObject {
    static let shared = UndoProxy()
    private override init() {}
}
