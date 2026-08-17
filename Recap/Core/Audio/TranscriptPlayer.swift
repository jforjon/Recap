import Foundation
import AVFoundation
import Observation

/// Plays a recording back and reports where it has got to, so the transcript can
/// follow along.
///
/// Deliberately small: one file, one player, a timer that ticks while playing.
/// The transcript view derives the highlighted segment from `currentTime` rather
/// than being told about it, so there is exactly one source of truth.
@MainActor
@Observable
final class TranscriptPlayer {
    struct PlayerError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private(set) var isPlaying = false
    private(set) var isPreparing = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var errorMessage: String?

    /// Playback speed. Long lectures are the main use case, and nobody listens
    /// back to a two-hour talk at 1×.
    var rate: Float = 1.0 {
        didSet {
            player?.rate = rate
            if isPlaying { player?.play() }
        }
    }

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    private var loadedNoteId: UUID?

    // No deinit teardown: the ticker holds `self` weakly and returns as soon as
    // it's gone, and `deinit` on a main-actor class can't touch isolated state.

    /// Loads the audio for a note, pulling it back from iCloud first if the system
    /// has evicted the local copy. Safe to call repeatedly — reloading the same
    /// note is a no-op so `.task` re-runs don't restart playback.
    func load(noteId: UUID) async {
        guard loadedNoteId != noteId else { return }
        guard let url = AudioStore.existingURL(for: noteId) else {
            reset()
            return
        }

        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }

        do {
            try await AudioStore.ensureDownloaded(url)

            // `.playback` so audio comes out of the speaker rather than the
            // earpiece, and keeps going when the phone is locked.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()

            self.player = player
            duration = player.duration
            currentTime = 0
            loadedNoteId = noteId
        } catch {
            reset()
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "This recording couldn't be played."
        }
    }

    var hasAudio: Bool { player != nil }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTicker()
        } else {
            // Restart from the top once the end has been reached, rather than
            // leaving Play doing nothing.
            if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
            player.play()
            isPlaying = true
            startTicker()
        }
    }

    func seek(to time: Double) {
        guard let player else { return }
        let clamped = max(0, min(time, player.duration))
        player.currentTime = clamped
        currentTime = clamped
    }

    func skip(by delta: Double) {
        seek(to: currentTime + delta)
    }

    func stop() {
        player?.pause()
        isPlaying = false
        stopTicker()
    }

    private func reset() {
        stopTicker()
        player = nil
        loadedNoteId = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    /// 20 Hz — fast enough that the highlight lands on the right words, slow
    /// enough to be invisible on the battery next to audio decoding.
    private func startTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    return
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    static func formatTime(_ seconds: Double) -> String { formatTimecode(seconds) }
}
