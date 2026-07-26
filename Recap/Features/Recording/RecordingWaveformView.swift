import SwiftUI

/// Live waveform driven by the microphone's loudness. Each bar is one sample of
/// recent audio level (oldest on the left, newest on the right), so the shape
/// reacts to the speaker's voice in real time instead of scrolling generically.
struct RecordingWaveformView: View {
    /// Normalized loudness history (0...1), oldest first.
    let levels: [CGFloat]

    private let minHeight: CGFloat = 4
    private let maxBarWidth: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let count = levels.count
            guard count > 0 else { return }

            let slot = size.width / CGFloat(count)
            let barWidth = min(maxBarWidth, slot * 0.6)
            let midY = size.height / 2

            for (index, level) in levels.enumerated() {
                let height = minHeight + (size.height - minHeight) * level
                let x = CGFloat(index) * slot + (slot - barWidth) / 2
                let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(AppColors.accent)
                )
            }
        }
        .frame(height: 36)
        .clipped()
    }
}
