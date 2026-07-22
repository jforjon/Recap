import AVFoundation

/// Thin wrapper around AVAudioRecorder — records one chunk file at a time to disk.
final class AudioChunkRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var currentChunkURL: URL?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }

    func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Starts recording a new chunk directly to `url`. The file exists on disk
    /// from this point on, before any network call happens.
    func startChunk(at url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        recorder.record()
        self.recorder = recorder
        self.currentChunkURL = url
    }

    /// Stops and finalizes the current chunk file, returning its URL. AVAudioRecorder.stop()
    /// flushes and closes the file synchronously, so the file is safe to read immediately after.
    @discardableResult
    func stopChunk() -> URL? {
        recorder?.stop()
        let url = currentChunkURL
        recorder = nil
        currentChunkURL = nil
        return url
    }

    /// Discards the current chunk without keeping the file (used when the user trashes a recording).
    func stopAndDeleteChunk() {
        recorder?.stop()
        if let url = currentChunkURL {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        currentChunkURL = nil
    }
}
