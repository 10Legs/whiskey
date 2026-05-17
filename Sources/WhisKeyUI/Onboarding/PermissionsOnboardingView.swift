import AppKit
import SwiftUI
import WhisKeyCore

// MARK: - Model Types

public enum OnboardingStep: Int, CaseIterable {
    case microphone = 0
    case accessibility = 1
    case inputMonitoring = 2
    case complete = 3
}

public enum StepState: Equatable {
    case idle
    case waiting
    case granted
    case denied
    case restricted
    case skipped
}

// MARK: - VoiceOver helper (macOS)

private func postAXAnnouncement(_ message: String) {
    NSAccessibility.post(
        element: NSApp,
        notification: .announcementRequested,
        userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: message as NSString]
    )
}

// MARK: - ViewModel

@MainActor
@Observable
final class OnboardingViewModel {

    var currentStep: OnboardingStep
    var micState: StepState = .idle
    var accessibilityState: StepState = .idle
    var inputMonitoringState: StepState = .idle
    var inputMonitoringSkipped = false

    private let permissions: PermissionsManager
    private var pollingTask: Task<Void, Never>?
    private let onComplete: () -> Void

    init(permissions: PermissionsManager, onComplete: @escaping () -> Void) {
        self.permissions = permissions
        self.onComplete = onComplete

        // Resume from last incomplete step persisted across restarts
        let savedStep = UserDefaults.standard.integer(forKey: "onboardingLastStep")
        self.currentStep = OnboardingStep(rawValue: savedStep) ?? .microphone

        // Reflect already-granted states when resuming mid-flow
        if permissions.status(for: .microphone) == .granted {
            micState = .granted
        }
        if AXIsProcessTrusted() {
            accessibilityState = .granted
        }
        if CGPreflightListenEventAccess() {
            inputMonitoringState = .granted
        }
        if UserDefaults.standard.bool(forKey: "inputMonitoringSkipped") {
            inputMonitoringSkipped = true
        }
    }

    // MARK: - Microphone

    func requestMicrophone() {
        permissions.requestMicrophone { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted {
                    self.micState = .granted
                    postAXAnnouncement("Microphone permission granted")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    self.advance()
                } else {
                    let status = self.permissions.status(for: .microphone)
                    self.micState = status == .restricted ? .restricted : .denied
                }
            }
        }
    }

    func checkMicrophoneAgain() {
        let status = permissions.status(for: .microphone)
        if status == .granted {
            micState = .granted
            postAXAnnouncement("Microphone permission granted")
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                advance()
            }
        }
        // If still denied, remain in denied state — no feedback loop
    }

    func openMicrophoneSettings() {
        permissions.openMicrophoneSettings()
    }

    // MARK: - Accessibility polling

    func startAccessibilityPolling() {
        accessibilityState = .waiting
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                if AXIsProcessTrusted() {
                    accessibilityState = .granted
                    postAXAnnouncement("Accessibility permission granted")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    if !Task.isCancelled {
                        advance()
                    }
                    break
                }
            }
        }
    }

    func openAccessibilitySettings() {
        permissions.openAccessibilitySettings()
        if accessibilityState == .idle {
            startAccessibilityPolling()
        }
    }

    // MARK: - Input Monitoring polling

    func startInputMonitoringPolling() {
        inputMonitoringState = .waiting
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                if CGPreflightListenEventAccess() {
                    inputMonitoringState = .granted
                    postAXAnnouncement("Input Monitoring permission granted")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    if !Task.isCancelled {
                        advance()
                    }
                    break
                }
            }
        }
    }

    func openInputMonitoringSettings() {
        // Call CGRequestListenEventAccess() first so the app registers itself in
        // System Settings > Privacy & Security > Input Monitoring. Without this call
        // the app never appears in the list and the user cannot grant access.
        // CGPreflightListenEventAccess() (used for status checks) does NOT register
        // the app — only CGRequestListenEventAccess() does.
        permissions.requestInputMonitoringAccess()
        permissions.openInputMonitoringSettings()
        if inputMonitoringState == .idle {
            startInputMonitoringPolling()
        }
    }

    func skipInputMonitoring() {
        pollingTask?.cancel()
        inputMonitoringSkipped = true
        UserDefaults.standard.set(true, forKey: "inputMonitoringSkipped")
        advance()
    }

    // MARK: - Navigation

    func advance() {
        pollingTask?.cancel()
        let next: OnboardingStep
        switch currentStep {
        case .microphone:
            next = .accessibility
        case .accessibility:
            next = .inputMonitoring
        case .inputMonitoring:
            next = .complete
        case .complete:
            finishOnboarding()
            return
        }
        currentStep = next
        UserDefaults.standard.set(next.rawValue, forKey: "onboardingLastStep")
        announceStep(next)
    }

    private func announceStep(_ step: OnboardingStep) {
        let text: String
        switch step {
        case .microphone:
            text = "Step 1 of 3 — Microphone permission"
        case .accessibility:
            text = "Step 2 of 3 — Accessibility permission"
        case .inputMonitoring:
            text = "Step 3 of 3 — Input Monitoring permission"
        case .complete:
            text = "Setup complete. WhisKey is ready to use."
        }
        postAXAnnouncement(text)
    }

    func finishOnboarding() {
        pollingTask?.cancel()
        UserDefaults.standard.removeObject(forKey: "onboardingLastStep")
        onComplete()
    }

    func stopPolling() {
        pollingTask?.cancel()
    }
}

// MARK: - Root View

public struct PermissionsOnboardingView: View {

    @State private var viewModel: OnboardingViewModel
    @State private var reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    public init(permissions: PermissionsManager, onComplete: @escaping () -> Void) {
        _viewModel = State(
            wrappedValue: OnboardingViewModel(permissions: permissions, onComplete: onComplete)
        )
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingHeaderView(
                    currentStep: viewModel.currentStep,
                    reduceMotion: reduceMotion
                )

                Divider()
                    .padding(.horizontal, 16)

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
            }
        }
        .frame(width: 540, height: 480)
        .onAppear {
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            )
        ) { _ in
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        let stepTransition: AnyTransition = reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )

        Group {
            switch viewModel.currentStep {
            case .microphone:
                VStack(spacing: 24) {
                    PermissionStepView(
                        step: .microphone,
                        state: viewModel.micState,
                        reduceMotion: reduceMotion
                    )
                    OnboardingActionBar(
                        step: .microphone,
                        state: viewModel.micState,
                        onPrimary: { handlePrimary() },
                        onSecondary: { handleSecondary() },
                        onSkip: nil
                    )
                }
                .transition(stepTransition)

            case .accessibility:
                VStack(spacing: 24) {
                    PermissionStepView(
                        step: .accessibility,
                        state: viewModel.accessibilityState,
                        reduceMotion: reduceMotion
                    )
                    OnboardingActionBar(
                        step: .accessibility,
                        state: viewModel.accessibilityState,
                        onPrimary: { handlePrimary() },
                        onSecondary: { handleSecondary() },
                        onSkip: nil
                    )
                }
                .transition(stepTransition)

            case .inputMonitoring:
                VStack(spacing: 24) {
                    PermissionStepView(
                        step: .inputMonitoring,
                        state: viewModel.inputMonitoringState,
                        reduceMotion: reduceMotion
                    )
                    OnboardingActionBar(
                        step: .inputMonitoring,
                        state: viewModel.inputMonitoringState,
                        onPrimary: { handlePrimary() },
                        onSecondary: { handleSecondary() },
                        onSkip: { viewModel.skipInputMonitoring() }
                    )
                }
                .transition(stepTransition)

            case .complete:
                OnboardingCompletionView(
                    skippedInputMonitoring: viewModel.inputMonitoringSkipped,
                    onStart: { viewModel.finishOnboarding() }
                )
                .transition(.opacity)
            }
        }
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.18)
                : .easeInOut(duration: 0.28),
            value: viewModel.currentStep
        )
    }

    private func handlePrimary() {
        switch viewModel.currentStep {
        case .microphone:
            switch viewModel.micState {
            case .idle:
                viewModel.requestMicrophone()
            case .denied:
                viewModel.openMicrophoneSettings()
            case .restricted:
                break
            case .granted:
                viewModel.advance()
            case .waiting, .skipped:
                break
            }
        case .accessibility:
            viewModel.openAccessibilitySettings()
        case .inputMonitoring:
            viewModel.openInputMonitoringSettings()
        case .complete:
            viewModel.finishOnboarding()
        }
    }

    private func handleSecondary() {
        switch viewModel.currentStep {
        case .microphone:
            viewModel.checkMicrophoneAgain()
        case .accessibility:
            viewModel.openAccessibilitySettings()
        case .inputMonitoring:
            viewModel.openInputMonitoringSettings()
        case .complete:
            break
        }
    }
}
