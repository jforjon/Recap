import SwiftUI

/// Live waveform driven by the microphone's loudness.
///
/// Each bar oscillates in place on its own loop rather than the row scrolling
/// right-to-left, so the shape reads as a level meter breathing with the voice
/// instead of a chart of the recent past. Loudness sets the amplitude of that
/// oscillation: silence leaves a low idle shimmer, speech swings the bars out to
/// their full height.
///
/// The row fills whatever width it is given: the bar pitch is fixed and the
/// count follows from it, so the density is the same on every device and the
/// meter never leaves a gap beside the elapsed time.
struct RecordingWaveformView: View {
    /// Current smoothed loudness, 0...1.
    let level: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let minHeight: CGFloat = 7
    private let maxHeight: CGFloat = 28

    var body: some View {
        Group {
            if reduceMotion {
                // Frozen mid-swing. Still tracks loudness — it's the motion that
                // is unwelcome, not the feedback.
                canvas { _ in 0.5 }
            } else {
                TimelineView(.animation) { timeline in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    canvas { index in
                        // Each bar runs its own period and starts part-way into
                        // it, so the row never pulses as one block.
                        let period = 0.45 + 0.25 * jitter(index, salt: 2)
                        let stagger = 0.22 * jitter(index, salt: 3)
                        return 0.5 - 0.5 * cos(2 * .pi * (now - stagger) / period)
                    }
                }
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.12), value: level)
    }

    /// - Parameter swing: where in its cycle a given bar is, 0...1.
    private func canvas(swing: @escaping (Int) -> Double) -> some View {
        Canvas { context, size in
            // As many bars as fit at the fixed pitch. Whatever is left over is
            // under one pitch — a couple of points, split either side — so
            // centring the run reads as flush without stretching the gaps.
            let barCount = max(1, Int((size.width + barSpacing) / (barWidth + barSpacing)))
            let totalWidth = CGFloat(barCount) * barWidth
                + CGFloat(barCount - 1) * barSpacing
            let originX = (size.width - totalWidth) / 2
            let midY = size.height / 2

            // A floor under the amplitude keeps a little life in the row while
            // nobody is speaking, which is what tells you the mic is still open.
            let amplitude = 0.15 + 0.85 * min(max(level, 0), 1)

            for index in 0..<barCount {
                // The bar's own ceiling, so the row is irregular the way a real
                // meter is — deterministic, so it never differs between launches.
                let peak = minHeight + (maxHeight - minHeight)
                    * CGFloat(0.35 + 0.65 * jitter(index, salt: 1))
                // Bars travel between a quarter of their height and all of it;
                // loudness scales how far along that travel they actually get.
                let scale = 0.25 + 0.75 * CGFloat(swing(index))
                let height = minHeight + (peak - minHeight) * scale * amplitude

                let x = originX + CGFloat(index) * (barWidth + barSpacing)
                let rect = CGRect(x: x, y: midY - height / 2,
                                  width: barWidth, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(AppColors.accentGraphic)
                )
            }
        }
    }

    /// Stable pseudo-random in 0..<1 for a bar, so each gets its own height,
    /// period and offset without hard-coding fifteen magic numbers.
    private func jitter(_ index: Int, salt: Int) -> Double {
        let x = sin(Double(index) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
}
