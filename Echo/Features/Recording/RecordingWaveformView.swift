import SwiftUI

/// 1:1 port of the scrolling waveform bars in RecordingBar.tsx / .module.css —
/// same bar heights, same 3px width / 2px gap, same 21s seamless scroll loop.
struct RecordingWaveformView: View {
    private static let heights: [CGFloat] = [
        12,22,30,18,28,10,34,20,26,14,32,16,24,10,28,18,32,12,22,8,30,16,26,20,
        14,28,10,22,18,32,14,24,28,12,20,32,10,26,18,30,22,8,34,16,28,12,24,18,
        32,20,14,26,10,22,30,16,28,12,20,32,
    ]
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2
    private static let setWidth: CGFloat = CGFloat(heights.count) * (barWidth + barSpacing)
    private static let scrollDuration: Double = 21

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let speed = Self.setWidth / Self.scrollDuration
                let offset = (elapsed * speed).truncatingRemainder(dividingBy: Self.setWidth)

                let setsNeeded = Int(ceil((size.width + Self.setWidth) / Self.setWidth)) + 1
                let midY = size.height / 2
                var x = -offset

                for _ in 0..<setsNeeded {
                    for height in Self.heights {
                        if x > -Self.barWidth, x < size.width {
                            let rect = CGRect(x: x, y: midY - height / 2, width: Self.barWidth, height: height)
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: Self.barWidth / 2),
                                with: .color(AppColors.neutral800)
                            )
                        }
                        x += Self.barWidth + Self.barSpacing
                    }
                }
            }
        }
        .frame(height: 36)
        .clipped()
    }
}
