import SwiftUI

/// The capture screen, shown full-screen for as long as the mic is open.
///
/// Recording is a single-task mode: there is nothing useful to do in the Library
/// while a talk is being captured, and a bar pinned under a scrolling list
/// invited exactly that — browsing away from the thing being recorded, with the
/// live transcript clipped to three lines behind it. Full-screen gives the
/// transcript the room to be read back, and leaves one way out per intent:
/// dismiss to discard, send to save.
struct RecordingSessionView: View {
    let recordingManager: RecordingManager

    @State private var showDiscardConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        // The X sits where "close" normally does, so it has to be able to mean
        // "not that" — the transcript is gone for good once it's confirmed.
        .alert("Discard recording?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) { recordingManager.discardRecording() }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("Everything said so far is deleted. This can't be undone.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: Spacing.s2) {
            RecordingIndicatorDot()
            Text("Recording")
                .appTextStyle(.label)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Button {
                showDiscardConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.appIcon)
            .accessibilityLabel("Discard recording")
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.top, Spacing.s3)
        .padding(.bottom, Spacing.s5)
    }

    private var transcript: some View {
        ScrollView {
            Text(recordingManager.liveTranscript.isEmpty
                 ? "Listening…"
                 : recordingManager.liveTranscript)
                .appTextStyle(.body)
                .foregroundStyle(recordingManager.liveTranscript.isEmpty
                                 ? AppColors.textTertiary
                                 : AppColors.textPrimary)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s5)
                .padding(.bottom, Spacing.s5)
        }
        // Pins the view to the newest words as the transcript grows, so the
        // screen behaves like a live caption rather than a document.
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: Spacing.s4) {
            // Elapsed, meter, send on one line: the duration reads at the leading
            // edge where a running clock is expected, the meter takes every point
            // between, and send sits where a composer's send button sits. The row
            // height is pinned so it can't shift as the digits or bars change.
            HStack(spacing: Spacing.s4) {
                Text(formattedElapsed)
                    .appTextStyle(.monoLarge)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(minWidth: 46, alignment: .leading)
                    .monospacedDigit()

                RecordingWaveformView(level: recordingManager.audioLevel)
                    .frame(maxWidth: .infinity)

                Button {
                    recordingManager.stopRecording()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .background(AppColors.accent)
                        .foregroundStyle(AppColors.accentText)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save recording")
            }
            .frame(height: 48)

            Text("Transcribed on device — nothing leaves your phone.")
                .appTextStyle(.small)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.s5)
        .padding(.top, Spacing.s4)
        .padding(.bottom, Spacing.s5)
        .frame(maxWidth: .infinity)
        .background(
            AppColors.background
                .overlay(AppColors.separator.frame(height: 1), alignment: .top)
        )
    }

    private var formattedElapsed: String {
        let m = recordingManager.elapsed / 60
        let s = recordingManager.elapsed % 60
        return String(format: "%02d:%02d", m, s)
    }
}

/// The one thing on the screen that has to say "this is live". Reduce Motion
/// gets the dot without the pulse.
private struct RecordingIndicatorDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDim = false

    var body: some View {
        Circle()
            .fill(AppColors.destructive)
            .frame(width: 8, height: 8)
            .opacity(isDim ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                       value: isDim)
            .onAppear { if !reduceMotion { isDim = true } }
    }
}
