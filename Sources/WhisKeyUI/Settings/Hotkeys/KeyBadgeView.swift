import SwiftUI
import WhisKeyCore

/// Renders a key combo in macOS standard notation inside a rounded badge.
///
/// Used in both the bound-state table cell and the conflict-state capture zone preview.
/// When `displayString` is "Not set", renders plain italic text with no background badge.
public struct KeyBadgeView: View {

    public let binding: HotkeyBinding

    public init(binding: HotkeyBinding) {
        self.binding = binding
    }

    public var body: some View {
        if binding.keyCode == nil {
            // "Not set" — plain italic text, no badge.
            Text("Not set")
                .font(.system(size: 13))
                .italic()
                .foregroundStyle(.tertiary)
        } else {
            Text(binding.displayString)
                .font(.system(size: 13, design: .monospaced).weight(.medium))
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.quaternary)
                )
        }
    }
}

// MARK: - Preview Badge for capture zone conflict state

/// A compact badge that renders an arbitrary combo string (used inside the capture zone
/// when a conflict is detected — at that point we have the keyCode but it isn't saved yet).
public struct KeyComboPreviewBadge: View {

    public let comboString: String

    public init(comboString: String) {
        self.comboString = comboString
    }

    public var body: some View {
        Text(comboString)
            .font(.system(size: 13, design: .monospaced).weight(.medium))
            .foregroundStyle(.primary)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.quaternary)
            )
    }
}
