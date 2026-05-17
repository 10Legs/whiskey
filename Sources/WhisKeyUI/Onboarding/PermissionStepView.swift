import AppKit
import SwiftUI

// MARK: - WaitingStateView (inline per naming contract)

struct WaitingStateView: View {

    let step: OnboardingStep
    let reduceMotion: Bool
    @State private var pulseScale: CGFloat = 1.0
    @State private var showLongWait = false
    @State private var waitTimer: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            if reduceMotion {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .strokeBorder(Color(nsColor: .systemOrange), lineWidth: 2)
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 1.4)
                            .repeatForever(autoreverses: true)
                        ) {
                            pulseScale = 1.12
                        }
                    }
                    .onDisappear {
                        pulseScale = 1.0
                    }
            }

            Text(showLongWait
                 ? "Still waiting… Switch WhisKey on in the Accessibility list."
                 : "Waiting for you to enable WhisKey in System Settings…")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: showLongWait)
        }
        .onAppear {
            waitTimer = Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if !Task.isCancelled {
                    showLongWait = true
                }
            }
        }
        .onDisappear {
            waitTimer?.cancel()
            waitTimer = nil
        }
    }
}

// MARK: - PermissionStepView

public struct PermissionStepView: View {

    let step: OnboardingStep
    let state: StepState
    let reduceMotion: Bool

    public var body: some View {
        ZStack {
            // Card base
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)

            // State-driven tint overlay
            RoundedRectangle(cornerRadius: 10)
                .fill(cardTint)
                .animation(.easeInOut(duration: 0.2), value: state)

            // Card content
            VStack(spacing: 16) {
                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(iconColor)
                    .frame(width: 40, height: 40)
                    .accessibilityLabel(iconAccessibilityLabel)

                // Headline
                Text(headline)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(headlineColor)
                    .multilineTextAlignment(.center)

                // Body copy
                Text(bodyText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                // Status area
                statusArea
            }
            .padding(20)
        }
    }

    // MARK: - Status Area

    @ViewBuilder
    private var statusArea: some View {
        switch state {
        case .idle, .denied, .restricted:
            EmptyView()
        case .waiting:
            Divider()
            WaitingStateView(step: step, reduceMotion: reduceMotion)
        case .granted:
            PermissionGrantedBadge()
        case .skipped:
            EmptyView()
        }
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch step {
        case .microphone:
            switch state {
            case .denied: return "mic.slash.fill"
            case .restricted: return "exclamationmark.triangle.fill"
            default: return "mic.fill"
            }
        case .accessibility: return "hand.point.up.left.fill"
        case .inputMonitoring: return "keyboard.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch step {
        case .microphone:
            switch state {
            case .denied: return Color(nsColor: .systemRed)
            case .restricted: return Color(nsColor: .systemOrange)
            default: return Color.primary
            }
        default: return Color.primary
        }
    }

    private var iconAccessibilityLabel: String {
        switch step {
        case .microphone:
            switch state {
            case .denied: return "Microphone denied"
            case .restricted: return "Warning"
            default: return "Microphone"
            }
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Keyboard"
        case .complete: return "Checkmark"
        }
    }

    private var headline: String {
        switch step {
        case .microphone:
            switch state {
            case .denied: return "Microphone access is required"
            case .restricted: return "Microphone access is restricted"
            default: return "WhisKey needs to hear you"
            }
        case .accessibility:
            return "Allow WhisKey to type for you"
        case .inputMonitoring:
            return "Enable the global hotkey (recommended)"
        case .complete:
            return "You're ready to transcribe"
        }
    }

    private var headlineColor: Color {
        switch state {
        case .denied: return Color(nsColor: .systemRed)
        default: return Color.primary
        }
    }

    private var bodyText: String {
        switch step {
        case .microphone:
            switch state {
            case .denied:
                return "WhisKey can't transcribe without microphone access. To enable it, open System Settings → Privacy & Security → Microphone and switch on WhisKey."
            case .restricted:
                return "Microphone access is restricted on this Mac. Contact your administrator."
            default:
                return "To capture your voice for transcription, WhisKey needs access to your microphone. Your audio is processed entirely on this Mac — it never leaves your machine."
            }
        case .accessibility:
            return "To inject transcribed text into whatever window you're focused on — Slack, VS Code, Safari, anywhere — WhisKey needs Accessibility access. This is how the text appears at your cursor.\n\nYou'll need to enable this manually in System Settings."
        case .inputMonitoring:
            return "WhisKey uses a global hotkey to start and stop recording from anywhere on your Mac — even when WhisKey isn't the focused window. If you skip this, you can still trigger recording from the menu bar.\n\nYou'll need to enable this manually in System Settings."
        case .complete:
            return "Hold your hotkey, speak, and your words will appear wherever your cursor is. Everything stays on your Mac."
        }
    }

    private var cardTint: Color {
        switch state {
        case .idle: return .clear
        case .waiting: return Color(nsColor: .systemOrange).opacity(0.10)
        case .granted: return Color.accentColor.opacity(0.12)
        case .denied, .restricted: return Color(nsColor: .systemRed).opacity(0.12)
        case .skipped: return .clear
        }
    }
}
