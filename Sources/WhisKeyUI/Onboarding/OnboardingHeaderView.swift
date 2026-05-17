import SwiftUI

// MARK: - OnboardingProgressDots (inline per naming contract)

struct OnboardingProgressDots: View {

    let currentStep: OnboardingStep
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                dot(for: index)
            }
        }
    }

    @ViewBuilder
    private func dot(for index: Int) -> some View {
        let stepIndex = currentStep.rawValue
        if index < stepIndex {
            // Completed
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 5, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .accessibilityLabel("Step \(index + 1) complete")
        } else if index == stepIndex {
            // Active
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Step \(index + 1), current")
        } else {
            // Inactive
            Circle()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 6, height: 6)
                .accessibilityLabel("Step \(index + 1) pending")
        }
    }
}

// MARK: - OnboardingHeaderView

public struct OnboardingHeaderView: View {

    let currentStep: OnboardingStep
    let reduceMotion: Bool

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .accessibilityHidden(true)

                Text("WhisKey")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)

                Spacer()

                if currentStep != .complete {
                    OnboardingProgressDots(
                        currentStep: currentStep,
                        reduceMotion: reduceMotion
                    )
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.3, dampingFraction: 0.7),
                        value: currentStep
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}
