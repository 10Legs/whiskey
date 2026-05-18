import SwiftUI

/// Generic section container for the Halide design system.
///
/// Replaces the legacy `PhosphorSection` and `PhosphorToneSection` types.
/// Renders a caption-weight section title, a `Divider`, and the caller-provided
/// content inside a card-shaped background with a subtle drop shadow.
public struct HalideSection<Content: View>: View {

    let title: String
    @ViewBuilder let content: () -> Content

    public init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HalideTokens.spacing8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(HalideTokens.textTertiary)

            Divider()

            content()
                .padding(HalideTokens.spacing12)
                .background(HalideTokens.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: HalideTokens.radiusMedium))
                .shadow(
                    color: Color.black.opacity(HalideTokens.cardShadowOpacity),
                    radius: HalideTokens.cardShadowRadius,
                    x: 0,
                    y: HalideTokens.cardShadowY
                )
        }
    }
}
