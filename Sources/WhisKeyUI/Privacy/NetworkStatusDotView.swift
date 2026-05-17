import SwiftUI
import WhisKeyCore

// MARK: - NetworkStatusDotView

/// A small filled circle badge reflecting the current EgressState.
///
/// Used in both the menu bar icon overlay and the popover header.
/// All state transitions respect Reduce Motion: the red-state initial pulse fires
/// once per state entry (tracked by `hasPulsed`) when Reduce Motion is off.
public struct NetworkStatusDotView: View {

    public let state: EgressState
    /// When true, the one-shot red pulse has already fired this session.
    @Binding public var hasPulsed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing: Bool = false

    public init(state: EgressState, hasPulsed: Binding<Bool>) {
        self.state = state
        self._hasPulsed = hasPulsed
    }

    public var body: some View {
        Group {
            if let color = dotColor {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isPulsing ? 1.6 : 1.0)
                    .opacity(isPulsing ? 0.4 : 1.0)
                    .accessibilityLabel(accessibilityLabel)
                    .onChange(of: state) { _, newState in
                        if newState == .unexpected && !hasPulsed && !reduceMotion {
                            triggerPulse()
                        }
                    }
            }
            // .unavailable: no dot rendered.
        }
    }

    // MARK: - Private

    private var dotColor: Color? {
        switch state {
        case .local:       return Color.green
        case .audited:     return Color.secondary
        case .unexpected:  return Color.red
        case .unavailable: return nil
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .local:       return "Network status: Local only — no egress"
        case .audited:     return "Network status: Cloud provider active"
        case .unexpected:  return "Network status: Warning — unexpected egress detected"
        case .unavailable: return "Network status: Monitoring unavailable"
        }
    }

    private func triggerPulse() {
        hasPulsed = true
        withAnimation(.easeInOut(duration: 0.4)) {
            isPulsing = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.easeInOut(duration: 0.2)) {
                isPulsing = false
            }
        }
    }
}
