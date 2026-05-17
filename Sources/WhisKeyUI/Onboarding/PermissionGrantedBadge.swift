import SwiftUI

/// Capsule badge shown when a permission step transitions to `.granted`.
/// Springs in on appearance, then auto-advance fires after 800ms from the ViewModel.
public struct PermissionGrantedBadge: View {

    @State private var appeared = false

    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Granted")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.12))
        )
        .accessibilityLabel("Permission granted")
        .scaleEffect(appeared ? 1.0 : 0.8)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}
