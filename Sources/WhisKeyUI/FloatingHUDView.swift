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

// MARK: - Waveform Render Context

/// Bundles waveform drawing inputs to stay within the 5-parameter limit.
private struct WaveformRenderContext {
    let phase: Double
    let level: Float
    let isRecording: Bool
    let reduceMotion: Bool
}

// MARK: - HUD View

/// Floating waveform HUD with two visual states:
/// - Idle (80×14): flat line / breathing oscillation in cool slate
/// - Recording (200×56): animated dual-sine oscilloscope with amber recording dot
///
/// Hosted inside FloatingHUDWindow. `PulsingModifier` has been removed —
/// the waveform itself signals recording state.
public struct WaveformHUDView: View {

    @ObservedObject var viewModel: FloatingHUDViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Halide sizing
    private let idleSize      = CGSize(width: 80, height: 14)
    private let recordingSize = CGSize(width: 200, height: 56)

    public init(viewModel: FloatingHUDViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let size = viewModel.isRecording ? recordingSize : idleSize
        let sizeAnimation: Animation? = reduceMotion
            ? nil
            : .spring(response: 0.35, dampingFraction: 0.75)

        ZStack(alignment: .leading) {
            // Recording indicator dot — static 6×6 pt, left-aligned, 10 pt inset.
            if viewModel.isRecording {
                Circle()
                    .fill(HalideTokens.accentRecording)
                    .frame(width: 6, height: 6)
                    .padding(.leading, 10)
                    .frame(maxHeight: .infinity, alignment: .center)
            }

            // Waveform / idle line — always present, centered.
            let isRecording = viewModel.isRecording
            let level = viewModel.audioLevel
            let noMotion = reduceMotion
            TimelineView(.animation) { timeline in
                Canvas { ctx, canvasSize in
                    let renderCtx = WaveformRenderContext(
                        phase: timeline.date.timeIntervalSinceReferenceDate,
                        level: level,
                        isRecording: isRecording,
                        reduceMotion: noMotion
                    )
                    drawWaveform(ctx: ctx, size: canvasSize, renderCtx: renderCtx)
                }
            }
            .padding(.horizontal, viewModel.isRecording ? 24 : 10)
        }
        .frame(width: size.width, height: size.height)
        .animation(sizeAnimation, value: viewModel.isRecording)
        .background {
            RoundedRectangle(cornerRadius: viewModel.isRecording ? HalideTokens.radiusXL : HalideTokens.radiusLarge)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: viewModel.isRecording ? HalideTokens.radiusXL : HalideTokens.radiusLarge)
                .stroke(HalideTokens.borderSubtle, lineWidth: 1)
        }
        .shadow(
            color: HalideTokens.hudShadowColor.opacity(HalideTokens.hudShadowOpacity),
            radius: HalideTokens.hudShadowRadius,
            x: 0,
            y: HalideTokens.hudShadowY
        )
        .accessibilityLabel(viewModel.isRecording ? "Recording in progress" : "WhisKey idle")
        .accessibilityHidden(false)
    }

    // MARK: - Waveform Drawing

    private func drawWaveform(ctx: GraphicsContext, size: CGSize, renderCtx: WaveformRenderContext) {
        let midY = size.height / 2
        let maxAmplitude = size.height / 2 - 4

        if renderCtx.isRecording {
            drawRecordingWaveform(ctx: ctx, size: size, midY: midY, maxAmplitude: maxAmplitude, renderCtx: renderCtx)
        } else {
            drawIdleLine(ctx: ctx, size: size, midY: midY, renderCtx: renderCtx)
        }
    }

    private func drawRecordingWaveform(
        ctx: GraphicsContext,
        size: CGSize,
        midY: CGFloat,
        maxAmplitude: CGFloat,
        renderCtx: WaveformRenderContext
    ) {
        let curved = CGFloat(pow(Double(max(renderCtx.level, 0)), 0.50))
        let amplitude = curved * maxAmplitude
        let phase = renderCtx.phase
        var path = Path()
        let steps = Int(size.width)

        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let noise = sin(fraction * 47.3 + phase * 3.7) * 0.15
            let yPos = midY - amplitude * CGFloat(
                sin(fraction * .pi * 5 + phase * 4.8) * 0.55 +
                sin(fraction * .pi * 9 + phase * 2.9) * 0.28 +
                sin(fraction * .pi * 13 + phase * 7.1) * 0.12 +
                noise
            )
            if step == 0 {
                path.move(to: CGPoint(x: CGFloat(step), y: yPos))
            } else {
                path.addLine(to: CGPoint(x: CGFloat(step), y: yPos))
            }
        }

        // Brightness: 75% → 100% as level rises from 0 → 1
        let opacity = 0.75 + Double(renderCtx.level) * 0.25
        ctx.stroke(
            path,
            with: .color(HalideTokens.textPrimary.opacity(opacity)),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawIdleLine(ctx: GraphicsContext, size: CGSize, midY: CGFloat, renderCtx: WaveformRenderContext) {
        // Breathing: ~8-second cycle, 2 pt peak-to-trough, disabled when reduceMotion.
        let breathingAmplitude: CGFloat = renderCtx.reduceMotion ? 0 : 2.0 * sin(renderCtx.phase * 0.8)
        let steps = Int(size.width)
        var path = Path()

        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let yPos = midY - breathingAmplitude * CGFloat(sin(fraction * .pi * 2))
            if step == 0 {
                path.move(to: CGPoint(x: CGFloat(step), y: yPos))
            } else {
                path.addLine(to: CGPoint(x: CGFloat(step), y: yPos))
            }
        }

        ctx.stroke(
            path,
            with: .color(HalideTokens.accentIdle),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
        )
    }
}
