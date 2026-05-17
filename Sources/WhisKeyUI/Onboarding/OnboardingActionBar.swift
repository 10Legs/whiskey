import SwiftUI

/// Bottom action area containing the primary button and optional secondary/skip controls.
/// Layout: VStack(spacing: 8), 16 pt horizontal insets, 16 pt bottom padding.
public struct OnboardingActionBar: View {

    let step: OnboardingStep
    let state: StepState
    let onPrimary: () -> Void
    let onSecondary: (() -> Void)?
    let onSkip: (() -> Void)?

    @State private var isPrimaryHovered = false
    @State private var isPrimaryPressed = false
    @State private var isSecondaryHovered = false

    public var body: some View {
        VStack(spacing: 8) {
            // Primary button — hidden in waiting state (waiting state has its own secondary)
            if state != .waiting && primaryLabel != nil {
                Button(action: onPrimary) {
                    Text(primaryLabel!)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    isPrimaryPressed
                                        ? Color.accentColor.opacity(0.85)
                                        : isPrimaryHovered
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
                .accessibilityAddTraits(.isButton)
            }

            // Waiting state: show "Open Settings Again" secondary button
            if state == .waiting {
                if let onSecondary {
                    secondaryButton(
                        label: "Open Settings Again",
                        action: onSecondary
                    )
                }
            } else {
                // Non-waiting secondary (e.g. "Check Again" for microphone denied)
                if let onSecondary, let secondaryLabel {
                    secondaryButton(label: secondaryLabel, action: onSecondary)
                }
            }

            // Skip — Input Monitoring only, always below primary/secondary
            if step == .inputMonitoring, let onSkip {
                Button(action: onSkip) {
                    Text("Skip for now — use menu bar only")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private func secondaryButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSecondaryHovered
                              ? AnyShapeStyle(Color.primary.opacity(0.1))
                              : AnyShapeStyle(.quaternary))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered in isSecondaryHovered = hovered }
        .contentShape(Rectangle())
        .frame(minHeight: 44)
    }

    // MARK: - Label logic

    private var primaryLabel: String? {
        switch step {
        case .microphone:
            switch state {
            case .idle: return "Allow Microphone Access"
            case .denied: return "Open Microphone Settings"
            case .restricted: return nil
            case .granted: return nil
            case .waiting, .skipped: return nil
            }
        case .accessibility:
            switch state {
            case .idle: return "Open Accessibility Settings"
            case .granted: return nil
            case .waiting: return nil
            default: return "Open Accessibility Settings"
            }
        case .inputMonitoring:
            switch state {
            case .idle: return "Open Input Monitoring Settings"
            case .granted: return nil
            case .waiting: return nil
            default: return "Open Input Monitoring Settings"
            }
        case .complete:
            return nil
        }
    }

    private var secondaryLabel: String? {
        switch step {
        case .microphone:
            switch state {
            case .denied: return "Check Again"
            default: return nil
            }
        default:
            return nil
        }
    }
}
