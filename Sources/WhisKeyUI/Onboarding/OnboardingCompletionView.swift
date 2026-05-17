import SwiftUI

/// Completion screen — replaces `PermissionStepView` when all required steps are done.
public struct OnboardingCompletionView: View {

    let skippedInputMonitoring: Bool
    let onStart: () -> Void

    @State private var isPrimaryHovered = false
    @State private var isPrimaryPressed = false

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Setup complete")

            VStack(spacing: 8) {
                Text("You're ready to transcribe")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)

                Text("Hold your hotkey, speak, and your words will appear wherever your cursor is. Everything stays on your Mac.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                if skippedInputMonitoring {
                    Text("Global hotkey is disabled. Enable it anytime in WhisKey Settings → Permissions.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }

            Spacer()

            Button(action: onStart) {
                Text("Start Using WhisKey")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                isPrimaryPressed || isPrimaryHovered
                                    ? Color.accentColor.opacity(0.85)
                                    : Color.accentColor
                            )
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(isPrimaryPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPrimaryPressed)
            .onHover { hovered in isPrimaryHovered = hovered }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPrimaryPressed = true }
                    .onEnded { _ in isPrimaryPressed = false }
            )
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
    }
}
