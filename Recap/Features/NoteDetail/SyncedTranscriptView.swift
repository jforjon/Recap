import SwiftUI

/// The Transcript tab: a player pinned at the top, and the transcript below it
/// broken into paragraphs that highlight and scroll as the recording plays.
///
/// Degrades in two steps rather than being all-or-nothing:
/// - no audio saved → paragraphs still render, from the segment timings alone
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            if player.hasAudio || player.isPreparing {
                playerBar
            }

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
        .task { await player.load(noteId: note.id) }
        .onDisappear { player.stop() }
    }

    // MARK: - Player

    private var playerBar: some View {
        VStack(spacing: Spacing.s3) {
            HStack(spacing: Spacing.s4) {
                Button {
                    player.skip(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 20))
                }
                .buttonStyle(.appIcon)
                .disabled(!player.hasAudio)

                Button {
                    followPlayback = true
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColors.accentText)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(AppColors.accent))
                }
                .buttonStyle(.plain)
                .disabled(!player.hasAudio)

                Button {
                    player.skip(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 20))
                }
                .buttonStyle(.appIcon)
                .disabled(!player.hasAudio)

                Spacer()

                Menu {
                    ForEach([Float(0.75), 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        AppMenuButton(
                            title: "\(speed.formatted())×",
                            systemImage: player.rate == speed ? "checkmark" : "speedometer"
                        ) {
                            player.rate = speed
                        }
                    }
                } label: {
                    Text("\(player.rate.formatted())×")
                        .appTextStyle(.monoMedium)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s2)
                        .background(Capsule().fill(AppColors.chipFill))
                }
            }

            scrubber

            HStack {
                Text(TranscriptPlayer.formatTime(player.currentTime))
                Spacer()
                Text(TranscriptPlayer.formatTime(player.duration))
            }
            .appTextStyle(.mono)
            .foregroundStyle(AppColors.neutral500)

            Button("Delete audio") {
                showDeleteAudioConfirm = true
            }
            .buttonStyle(.appDestructiveSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.s4)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var scrubber: some View {
        Slider(
            value: Binding(
                get: { player.currentTime },
                set: { player.seek(to: $0) }
            ),
            in: 0...max(player.duration, 0.1)
        )
        .tint(AppColors.accentGraphic)
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
