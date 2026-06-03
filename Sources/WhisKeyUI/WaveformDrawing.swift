import SwiftUI

// MARK: - Aurora Mirror Waveform

/// Single-waveform drawing namespace. Renders the "Aurora Mirror" style exclusively.
/// Two draw calls per frame: filled mirror shape + neon glow spine.
/// O(48) path construction. No ImageRenderer. No per-frame allocations beyond Path.
enum WaveformDrawing {

    // MARK: - Palette

    private static let quietCenter = Color(red: 0.47, green: 0.73, blue: 0.95)
    private static let loudCenter  = Color(red: 0.75, green: 0.90, blue: 1.0)
    private static let glowColor   = Color(red: 0.47, green: 0.73, blue: 0.95)

    // MARK: - Entry Point

    /// Draw the Aurora Mirror waveform into `context`.
    ///
    /// - Parameters:
    ///   - context: SwiftUI `GraphicsContext` provided by `Canvas`.
    ///   - size: Canvas size in points.
    ///   - samples: Rolling 48-sample audio level buffer (0.0–1.0), newest at the end.
    ///   - audioLevel: Smoothed peak amplitude (0.0–1.0) from ViewModel.
    ///   - time: `Date.timeIntervalSinceReferenceDate` from `TimelineView` for idle breathing.
    @MainActor
    static func draw(
        context: GraphicsContext,
        size: CGSize,
        samples: [Float],
        audioLevel: Float,
        time: TimeInterval
    ) {
        guard samples.count >= 2 else { return }

        let midY = size.height / 2
        let maxAmplitude = size.height / 2 - 4

        // Resolve active amplitude: idle breathing when silent, live samples when recording.
        let isIdle = audioLevel < 0.05
        let frame = FrameParams(midY: midY, maxAmplitude: maxAmplitude, time: time, isIdle: isIdle)
        let upperPoints = buildUpperPoints(samples: samples, size: size, frame: frame)

        let mirrorPath = buildMirrorPath(upperPoints: upperPoints, midY: midY, size: size)

        // -- Draw 1: amplitude-driven vertical gradient fill --
        let fillGradient = buildFillGradient(audioLevel: audioLevel, size: size, midY: midY, maxAmplitude: maxAmplitude)
        context.fill(mirrorPath, with: fillGradient)

        // -- Draw 2: neon glow spine (top curve only, no fill) --
        let spinePath = buildSpinePath(upperPoints: upperPoints)
        var glowContext = context
        glowContext.addFilter(.shadow(
            color: glowColor.opacity(0.8),
            radius: 8,
            x: 0,
            y: 0
        ))
        glowContext.stroke(
            spinePath,
            with: .color(glowColor.opacity(0.95)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        )
    }

    // MARK: - Point Construction

    private struct FrameParams {
        let midY: CGFloat
        let maxAmplitude: CGFloat
        let time: TimeInterval
        let isIdle: Bool
    }

    @MainActor
    private static func buildUpperPoints(
        samples: [Float],
        size: CGSize,
        frame: FrameParams
    ) -> [CGPoint] {
        let midY = frame.midY
        let maxAmplitude = frame.maxAmplitude
        let time = frame.time
        let isIdle = frame.isIdle
        let count = samples.count
        let stepX = size.width / CGFloat(count - 1)
        var points: [CGPoint] = []
        points.reserveCapacity(count)

        // Idle breathing sine amplitude — 4 pt peak, 1.4 Hz.
        let breathAmp: CGFloat = isIdle
            ? 4.0 * CGFloat(sin(time * 1.4 * .pi * 2))
            : 0.0

        for idx in 0..<count {
            let xPos = CGFloat(idx) * stepX
            let sampleVal = CGFloat(samples[idx]) * maxAmplitude
            let effective: CGFloat
            if isIdle {
                // Breathing: gentle sine shaped across the width.
                let fraction = Double(idx) / Double(count - 1)
                effective = abs(breathAmp * CGFloat(sin(fraction * .pi)))
            } else {
                effective = max(sampleVal, 1.0)
            }
            points.append(CGPoint(x: xPos, y: midY - effective))
        }
        return points
    }

    // MARK: - Path Construction

    /// Closed mirror path: top bezier curve, then mirrored bottom, closed.
    private static func buildMirrorPath(upperPoints: [CGPoint], midY: CGFloat, size: CGSize) -> Path {
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

        // Mirror: reverse the upper points reflected below midY.
        for idx in stride(from: upperPoints.count - 1, through: 0, by: -1) {
            let pt = upperPoints[idx]
            path.addLine(to: CGPoint(x: pt.x, y: midY + (midY - pt.y)))
        }
        path.closeSubpath()
        return path
    }

    /// Top curve only (spine path for glow stroke).
    private static func buildSpinePath(upperPoints: [CGPoint]) -> Path {
        var path = Path()
        guard upperPoints.count >= 2 else { return path }
        path.move(to: upperPoints[0])
        for idx in 0..<(upperPoints.count - 1) {
            let mid = CGPoint(
                x: (upperPoints[idx].x + upperPoints[idx + 1].x) / 2,
                y: (upperPoints[idx].y + upperPoints[idx + 1].y) / 2
            )
            path.addQuadCurve(to: mid, control: upperPoints[idx])
        }
        path.addLine(to: upperPoints[upperPoints.count - 1])
        return path
    }

    // MARK: - Gradient

    private static func buildFillGradient(
        audioLevel: Float,
        size: CGSize,
        midY: CGFloat,
        maxAmplitude: CGFloat
    ) -> GraphicsContext.Shading {
        // Normalise amplitude into 0–1 range across the quiet/loud thresholds.
        let quietThreshold: Float = 0.15
        let loudThreshold: Float  = 0.60
        let blendFactor = CGFloat(max(0, min(1, (audioLevel - quietThreshold) / (loudThreshold - quietThreshold))))

        // Lerp center color between quiet arctic blue and loud bright white-blue.
        let centerColor = blend(quietCenter, loudCenter, factor: blendFactor)

        // Quiet: 25% opacity at edges; loud: edges fade more aggressively.
        let edgeOpacity = 0.25 - 0.15 * blendFactor
        // Center opacity tracks loudness: 0.65 quiet → 0.95 loud.
        let centerOpacity = 0.65 + 0.30 * blendFactor

        let grad = Gradient(stops: [
            .init(color: centerColor.opacity(edgeOpacity), location: 0.0),
            .init(color: centerColor.opacity(centerOpacity), location: 0.5),
            .init(color: centerColor.opacity(edgeOpacity), location: 1.0)
        ])
        return .linearGradient(
            grad,
            startPoint: CGPoint(x: size.width / 2, y: midY - maxAmplitude),
            endPoint: CGPoint(x: size.width / 2, y: midY + maxAmplitude)
        )
    }

    // MARK: - Color Lerp

    private static func blend(_ colorA: Color, _ colorB: Color, factor: CGFloat) -> Color {
        // Both colors are in sRGB so component lerp is safe.
        let fA = 1.0 - factor
        return Color(
            red: 0.47 * fA + 0.75 * factor,
            green: 0.73 * fA + 0.90 * factor,
            blue: 0.95 * fA + 1.00 * factor
        )
    }
}
