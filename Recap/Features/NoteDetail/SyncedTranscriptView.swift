import SwiftUI

/// The Transcript tab: the transcript scrolls, broken into paragraphs that
/// highlight and follow the playhead, behind a compact player pinned to the
/// bottom of the screen.
///
/// The player is a `safeAreaInset` rather than an overlay, so it reserves its
/// own height and the last paragraph can still be scrolled clear of it. It owns
/// the scroll view for the same reason — this tab is deliberately outside the
/// note detail's shared one.
///
/// Degrades in two steps rather than being all-or-nothing:
/// - no audio saved → no player at all, and paragraphs still render from the
///   segment timings alone
/// - no timings either (anything recorded before this shipped) → the original
///   single block of text, exactly as before
struct SyncedTranscriptView: View {
    let note: Note
    @Binding var showDeleteAudioConfirm: Bool

    @State private var player = TranscriptPlayer()
    /// Suspended while the user is reading somewhere else in the transcript, so
    /// auto-scroll never yanks the page out from under them.
    @State private var followPlayback = true

    private var segments: [TranscriptSegment] { note.transcriptSegments ?? [] }
    private var paragraphs: [[TranscriptSegment]] { segments.paragraphs() }
    private var activeIndex: Int? {
        player.isPlaying || player.currentTime > 0
            ? segments.index(at: player.currentTime)
            : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let message = player.errorMessage {
                    Text(message)
                        .appTextStyle(.small)
                        .foregroundStyle(AppColors.destructiveText)
                }

                Text("TRANSCRIPT")
                    .appTextStyle(.label)
                    .foregroundStyle(AppColors.neutral600)

                if paragraphs.isEmpty {
                    untimedParagraphs
                } else {
                    paragraphList
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .recapBackground()
        .safeAreaInset(edge: .bottom) {
            // Nothing to pin without audio: the transcript takes the full height
            // back rather than leaving a dead bar across the bottom.
            if player.hasAudio || player.isPreparing {
                playerBar
            }
        }
        .task { await player.load(noteId: note.id) }
        .onDisappear { player.stop() }
    }

    // MARK: - Player

    private var playerBar: some View {
        VStack(spacing: Spacing.s2 - 2) {
            // Transport leads, then the two things that aren't playback controls.
            HStack(spacing: Spacing.s2) {
                skipButton(-15, icon: "gobackward.15")

                Button {
                    followPlayback = true
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.accentText)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(AppColors.accent))
                }
                .buttonStyle(.plain)
                .disabled(!player.hasAudio)

                skipButton(15, icon: "goforward.15")

                Spacer(minLength: Spacing.s2)

                Text("\(TranscriptPlayer.formatTime(player.currentTime)) / \(TranscriptPlayer.formatTime(player.duration))")
                    .appTextStyle(.mono)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()

                // An icon carries less warning than the words did, so the
                // confirmation before anything is deleted matters more here.
                Button {
                    showDeleteAudioConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 17))
                        .foregroundStyle(AppColors.destructiveText)
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete audio")
            }
            .frame(height: 44)

            HStack(spacing: Spacing.s3) {
                scrubber
                speedButton
            }
        }
        // Full width and flush to the bottom rather than a floating card: a
        // floating one leaves gaps down both sides and under it for the
        // transcript to scroll through, which reads as text bleeding past the
        // player. The background runs under the home indicator; the controls
        // stay above it.
        .padding(.horizontal, Spacing.s4)
        .padding(.top, Spacing.s3)
        .padding(.bottom, Spacing.s2)
        .background(
            AppColors.surface
                .overlay(AppColors.separator.frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func skipButton(_ seconds: TimeInterval, icon: String) -> some View {
        Button {
            player.skip(by: seconds)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(AppColors.textBright)
                .frame(width: 40, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!player.hasAudio)
    }

    /// Three speeds, cycled by tapping. A menu was a lot of ceremony for a
    /// control with this few values, and it put a popover over the transcript
    /// to choose between them.
    private static let speeds: [Float] = [1.0, 1.5, 2.0]

    private var speedButton: some View {
        Button {
            // "Next one up, then wrap" also lands anything set to an older,
            // since-removed speed back on a current one.
            player.rate = Self.speeds.first { $0 > player.rate } ?? Self.speeds[0]
        } label: {
            Text("\(player.rate.formatted())×")
                .appTextStyle(.mono)
                .foregroundStyle(AppColors.textBright)
                .monospacedDigit()
                // Fixed width so the scrubber doesn't resize as 1× becomes 1.5×.
                .frame(width: 30)
                .padding(.horizontal, Spacing.s2)
                .padding(.vertical, Spacing.s1 + 1)
                .background(Capsule().fill(AppColors.chipFill))
        }
        .buttonStyle(.plain)
        .disabled(!player.hasAudio)
        .accessibilityLabel("Playback speed, \(player.rate.formatted()) times")
    }

    /// Drawn by hand rather than using `Slider`: the system thumb is an oval that
    /// can't be reshaped, and a round handle is what the design calls for. The
    /// gesture earns its keep too — a bare binding can't also re-arm auto-scroll,
    /// which is what makes the transcript jump to wherever you scrubbed to.
    private var scrubber: some View {
        let trackHeight: CGFloat = 4
        let handleSize: CGFloat = 14

        return GeometryReader { geometry in
            let width = geometry.size.width
            // The track stops half a handle short at each end, so the handle
            // itself lands flush with the bar's padding at 0 and at the end
            // instead of bulging past it on the left.
            let inset = handleSize / 2
            let travel = max(width - handleSize, 1)
            let duration = max(player.duration, 0.1)
            let fraction = CGFloat(min(max(player.currentTime / duration, 0), 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: travel, height: trackHeight)
                    .offset(x: inset)
                Capsule()
                    .fill(AppColors.accentGraphic)
                    .frame(width: travel * fraction, height: trackHeight)
                    .offset(x: inset)
                Circle()
                    .fill(AppColors.accentText)
                    .frame(width: handleSize, height: handleSize)
                    .offset(x: travel * fraction)
            }
            .frame(width: width, height: geometry.size.height)
            // The whole strip is the target, not just the 4pt track.
            .contentShape(Rectangle())
            .gesture(
                // Zero minimum distance so a tap anywhere seeks, rather than
                // needing a drag to register.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        followPlayback = true
                        let ratio = min(max((value.location.x - inset) / travel, 0), 1)
                        player.seek(to: Double(ratio) * duration)
                    }
            )
        }
        .frame(height: 26)
        .disabled(!player.hasAudio)
    }

    // MARK: - Transcript

    /// Recorded before timing capture shipped, so there is nothing to sync to.
    /// Split on sentence boundaries instead — worse than real pause breaks, but
    /// it rescues the whole back catalogue from being one unbroken block.
    private var untimedParagraphs: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            ForEach(Array(TranscriptFormatting.paragraphs(from: note.transcript ?? "").enumerated()),
                    id: \.offset) { _, paragraph in
                Text(paragraph)
                    .appTextStyle(.body)
                    .foregroundStyle(AppColors.neutral800)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var paragraphList: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: Spacing.s4) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    paragraphRow(paragraph, index: index)
                }
            }
            .onChange(of: activeIndex) { _, _ in
                guard followPlayback, let paragraphIndex = activeParagraphIndex else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(paragraphIndex, anchor: .center)
                }
            }
        }
    }

    private func paragraphRow(_ paragraph: [TranscriptSegment], index: Int) -> some View {
        Button {
            guard player.hasAudio, let start = paragraph.first?.start else { return }
            followPlayback = true
            player.seek(to: start)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if player.hasAudio, let start = paragraph.first?.start {
                    Text(TranscriptPlayer.formatTime(start))
                        .appTextStyle(.mono)
                        .foregroundStyle(AppColors.neutral500)
                }
                Text(attributed(paragraph))
                    .appTextStyle(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        // Tapping only means something when there's audio to jump to.
        .disabled(!player.hasAudio)
        .id(index)
    }

    /// The paragraph as one run of text, with the segment currently being spoken
    /// picked out in amber and the rest dimmed once playback has started.
    private func attributed(_ paragraph: [TranscriptSegment]) -> AttributedString {
        var result = AttributedString()
        let active = activeIndex.map { segments[$0] }

        for (offset, segment) in paragraph.enumerated() {
            var piece = AttributedString(segment.text)
            if let active, active.start == segment.start {
                piece.foregroundColor = AppColors.accentGraphic
            } else {
                piece.foregroundColor = active == nil
                    ? AppColors.neutral800
                    : AppColors.textSecondary
            }
            result += piece
            if offset < paragraph.count - 1 { result += AttributedString(" ") }
        }
        return result
    }

    private var activeParagraphIndex: Int? {
        guard let activeIndex else { return nil }
        let active = segments[activeIndex]
        return paragraphs.firstIndex { paragraph in
            paragraph.contains { $0.start == active.start }
        }
    }
}
