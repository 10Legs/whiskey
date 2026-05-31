import SwiftUI

// MARK: - Waveform Drawing Namespace

/// Static drawing functions extracted from WaveformHUDView to keep type body size within limits.
/// All functions are pure — they take a GraphicsContext and render directly; no side effects.
enum WaveformDrawing {

    // MARK: - Entry Point

    @MainActor
    static func drawWaveform(ctx: GraphicsContext, size: CGSize, renderCtx: WaveformRenderContext) {
        let midY = size.height / 2
        let maxAmplitude = size.height / 2 - 4
        if renderCtx.isRecording {
            switch renderCtx.waveformStyle {
            case .pulseRibbon:
                drawPulseRibbon(ctx: ctx, size: size, midY: midY, maxAmplitude: maxAmplitude, renderCtx: renderCtx)
            case .rodArray:
                drawRodArray(ctx: ctx, size: size, midY: midY, maxAmplitude: maxAmplitude, renderCtx: renderCtx)
            case .liquidMercury:
                drawLiquidMercury(ctx: ctx, size: size, midY: midY, maxAmplitude: maxAmplitude, renderCtx: renderCtx)
            }
        } else {
            drawIdleLine(ctx: ctx, size: size, midY: midY, renderCtx: renderCtx)
        }
    }

    // MARK: - Pulse Ribbon

    @MainActor
    static func drawPulseRibbon(
        ctx: GraphicsContext,
        size: CGSize,
        midY: CGFloat,
        maxAmplitude: CGFloat,
        renderCtx: WaveformRenderContext
    ) {
        let samples = renderCtx.sampleBuffer
        guard samples.count >= 2 else { return }
        let count = samples.count
        let stepX = size.width / CGFloat(count - 1)

        // Build upper curve points
        var upperPoints: [CGPoint] = []
        let breathAmp: CGFloat = renderCtx.reduceMotion
            ? 1.0
            : max(1.0, CGFloat(pow(Double(max(renderCtx.level, 0.01)), 1.0)) * maxAmplitude)
        for idx in 0..<count {
            let xPos = CGFloat(idx) * stepX
            let amp = CGFloat(samples[idx]) * maxAmplitude
            let effective = max(amp, breathAmp * CGFloat(sin(renderCtx.phase * 1.2 + Double(idx) * 0.15) * 0.08 + 0.15))
            upperPoints.append(CGPoint(x: xPos, y: midY - effective))
        }

        // Smooth with quadratic bezier through midpoints
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: upperPoints[0])
        for idx in 0..<(upperPoints.count - 1) {
            let mid = CGPoint(
                x: (upperPoints[idx].x + upperPoints[idx + 1].x) / 2,
                y: (upperPoints[idx].y + upperPoints[idx + 1].y) / 2
            )
            path.addQuadCurve(to: mid, control: upperPoints[idx])
        }
        path.addLine(to: upperPoints[upperPoints.count - 1])
        path.addLine(to: CGPoint(x: size.width, y: midY))

        // Mirror lower half
        for idx in stride(from: upperPoints.count - 1, through: 0, by: -1) {
            let point = upperPoints[idx]
            path.addLine(to: CGPoint(x: point.x, y: midY + (midY - point.y)))
        }
        path.closeSubpath()

        // Vertical gradient fill
        let grad = Gradient(stops: [
            .init(color: Color.accentColor.opacity(0.9), location: 0.0),
            .init(color: Color.accentColor.opacity(0.35), location: 1.0)
        ])
        ctx.fill(
            path,
            with: .linearGradient(
                grad,
                startPoint: CGPoint(x: size.width / 2, y: midY - maxAmplitude),
                endPoint: CGPoint(x: size.width / 2, y: midY + maxAmplitude)
            )
        )
    }

    // MARK: - Rod Array

    @MainActor
    static func drawRodArray(
        ctx: GraphicsContext,
        size: CGSize,
        midY: CGFloat,
        maxAmplitude: CGFloat,
        renderCtx: WaveformRenderContext
    ) {
        let barCount = 32
        let barWidth: CGFloat = 2.5
        let gap: CGFloat = 3.0
        let totalW = CGFloat(barCount) * (barWidth + gap) - gap
        let startX = (size.width - totalW) / 2
        let phase = renderCtx.phase
        let samples = renderCtx.sampleBuffer

        for idx in 0..<barCount {
            let xPos = startX + CGFloat(idx) * (barWidth + gap)
            // Map bar index to sample buffer
            let sampleIdx = Int(Double(idx) / Double(barCount) * Double(samples.count))
            let rawAmp = CGFloat(samples[min(sampleIdx, samples.count - 1)])
            // Phase shimmer at low amplitude
            let shimmer = CGFloat(sin(phase * 3.0 + Double(idx) * 0.2) * 0.12)
            let amp = max(rawAmp + shimmer, 0.08) * maxAmplitude
            // Outer bars fade out
            let edge = min(idx, barCount - 1 - idx)
            let edgeFade: CGFloat = edge < 4 ? CGFloat(edge) / 4.0 : 1.0

            let barRect = CGRect(x: xPos, y: midY - amp, width: barWidth, height: amp * 2)
            let capsule = Path(roundedRect: barRect, cornerRadius: barWidth / 2)
            ctx.fill(capsule, with: .color(Color.primary.opacity(0.85 * edgeFade)))
        }
    }

    // MARK: - Liquid Mercury

    @MainActor
    static func drawLiquidMercury(
        ctx: GraphicsContext,
        size: CGSize,
        midY: CGFloat,
        maxAmplitude: CGFloat,
        renderCtx: WaveformRenderContext
    ) {
        let barCount = 28
        let barWidth: CGFloat = 5.0
        let gap: CGFloat = 3.0
        let totalW = CGFloat(barCount) * (barWidth + gap) - gap
        let startX = (size.width - totalW) / 2
        let samples = renderCtx.sampleBuffer
        let hueShift = Angle(degrees: sin(renderCtx.phase * 0.8) * 5.0)

        // Build the bar image using ImageRenderer (requires macOS 13+; project targets macOS 14).
        let renderer = ImageRenderer(content:
            Canvas { innerCtx, innerSize in
                for idx in 0..<barCount {
                    let xPos = startX + CGFloat(idx) * (barWidth + gap)
                    let sampleIdx = Int(Double(idx) / Double(barCount) * Double(samples.count))
                    let rawAmp = CGFloat(samples[min(sampleIdx, samples.count - 1)])
                    let amp = max(rawAmp, 0.10) * maxAmplitude
                    let barRect = CGRect(
                        x: xPos,
                        y: innerSize.height / 2 - amp,
                        width: barWidth,
                        height: amp * 2
                    )
                    innerCtx.fill(Path(roundedRect: barRect, cornerRadius: 3), with: .color(Color.accentColor))
                }
            }
            .frame(width: size.width, height: size.height)
            .blur(radius: 8)
            .contrast(15)
            .hueRotation(hueShift)
        )
        renderer.scale = 2.0
        if let nsImage = renderer.nsImage {
            ctx.draw(Image(nsImage: nsImage), in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Idle Line

    @MainActor
    static func drawIdleLine(
        ctx: GraphicsContext,
        size: CGSize,
        midY: CGFloat,
        renderCtx: WaveformRenderContext
    ) {
        // Breathing: ~8-second cycle, 2 pt peak-to-trough, disabled when reduceMotion.
        let breathingAmplitude: CGFloat = renderCtx.reduceMotion ? 0 : 3.5 * sin(renderCtx.phase * 0.8)
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
