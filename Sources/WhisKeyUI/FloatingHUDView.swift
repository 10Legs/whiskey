import Combine
import SwiftUI

// MARK: - View Model

/// Drives the floating HUD. Wired externally by AppDelegate via
/// `notifyRecordingStarted()` / `notifyRecordingStopped()` and by subscribing
/// to `AudioCaptureService.audioLevelPublisher`.
@MainActor
public final class FloatingHUDViewModel: ObservableObject {

    @Published public var isRecording: Bool = false
    @Published public var audioLevel: Float = 0.0

    private var levelCancellable: AnyCancellable?

    public init() {}

    /// Subscribe to a normalized audio level publisher (0.0–1.0).
    /// Typically sourced from TranscriptionPipeline.audioLevelPublisher.
    public func subscribe(toPublisher publisher: AnyPublisher<Float, Never>) {
        levelCancellable = publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
    }

    public func notifyRecordingStarted() {
        isRecording = true
    }

    public func notifyRecordingStopped() {
        isRecording = false
        // Decay level to zero so the waveform doesn't freeze on last value.
        audioLevel = 0.0
    }
}

// MARK: - HUD View

/// Floating waveform HUD with two visual states: idle (flat line) and
/// recording (animated oscilloscope). Hosted inside FloatingHUDWindow.
public struct WaveformHUDView: View {

    @ObservedObject var viewModel: FloatingHUDViewModel

    // Phosphor Ghost palette
    private let bgColor   = Color(red: 0.024, green: 0.031, blue: 0.031)
    private let neonGreen = Color(red: 0, green: 1, blue: 0.533)

    // Waveform geometry
    private let idleSize      = CGSize(width: 72, height: 12)
    private let recordingSize = CGSize(width: 96, height: 52)

    public init(viewModel: FloatingHUDViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let size = viewModel.isRecording ? recordingSize : idleSize

        ZStack(alignment: .topTrailing) {
            // Waveform canvas (recording state only)
            if viewModel.isRecording {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, canvasSize in
                        drawWaveform(
                            ctx: ctx,
                            size: canvasSize,
                            phase: timeline.date.timeIntervalSinceReferenceDate,
                            level: viewModel.audioLevel
                        )
                    }
                }
                .opacity(viewModel.isRecording ? 1 : 0)
                .animation(
                    .easeInOut(duration: 0.15).delay(viewModel.isRecording ? 0.1 : 0),
                    value: viewModel.isRecording
                )
                .frame(width: recordingSize.width, height: recordingSize.height)
            } else {
                // Idle: single flat line
                Rectangle()
                    .fill(neonGreen.opacity(0.30))
                    .frame(width: idleSize.width - 8, height: 1)
                    .frame(width: idleSize.width, height: idleSize.height)
            }

            // Pulsing dot — recording indicator (top-right)
            if viewModel.isRecording {
                Circle()
                    .fill(neonGreen)
                    .frame(width: 3, height: 3)
                    .padding(4)
                    .modifier(PulsingModifier())
            }
        }
        .frame(width: size.width, height: size.height)
        .background(bgColor)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(neonGreen, lineWidth: 1)
        )
        .cornerRadius(2)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
    }

    // MARK: - Waveform Drawing

    private func drawWaveform(
        ctx: GraphicsContext,
        size: CGSize,
        phase: Double,
        level: Float
    ) {
        let canvasWidth = size.width
        let canvasHeight = size.height
        let midY = canvasHeight / 2
        let amplitude = CGFloat(level) * (canvasHeight / 2 - 4)

        var path = Path()
        let steps = Int(canvasWidth)

        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            // Two sine waves at different frequencies + small noise term for organic feel
            let noise = sin(fraction * 47.3 + phase * 3.7) * 0.15
            let yPos = midY - amplitude * CGFloat(
                sin(fraction * .pi * 4 + phase * 5) * 0.6 +
                sin(fraction * .pi * 7 + phase * 3) * 0.3 +
                noise
            )
            if step == 0 {
                path.move(to: CGPoint(x: CGFloat(step), y: yPos))
            } else {
                path.addLine(to: CGPoint(x: CGFloat(step), y: yPos))
            }
        }

        ctx.stroke(
            path,
            with: .color(Color(red: 0, green: 1, blue: 0.533)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        )
    }
}

// MARK: - Pulsing Dot Modifier

private struct PulsingModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}
