import Foundation
@preconcurrency import AVFoundation
import Accelerate
import Speech

/// User's chosen transcription languages, persisted per-device (the language
/// models are downloaded per-device). The list is ordered; `defaultLanguage`
/// designates which one is preselected next to the Record button. Empty by
/// default — language selection is entirely optional.
enum SpokenLanguageStore {
    private static let selectedKey = "spokenLanguages.selected"
    private static let defaultKey = "spokenLanguages.default"

    /// BCP-47 identifiers the user has added (e.g. "en-US", "fr-FR").
    static var selected: [String] {
        get { UserDefaults.standard.stringArray(forKey: selectedKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: selectedKey) }
    }

    /// The language preselected next to Record. Falls back to the first selected.
    static var defaultLanguage: String? {
        get {
            if let stored = UserDefaults.standard.string(forKey: defaultKey), selected.contains(stored) {
                return stored
            }
            return selected.first
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultKey) }
    }

    static func toggle(_ code: String) {
        var current = selected
        if let index = current.firstIndex(of: code) {
            current.remove(at: index)
        } else {
            current.append(code)
        }
        selected = current
    }
}

/// On-device, streaming speech-to-text built on the iOS 26 `SpeechAnalyzer` /
/// `SpeechTranscriber` APIs. Captures the microphone through `AVAudioEngine` and
/// emits a live transcript with **no network and no third-party API** — so losing
/// signal never affects transcription.
///
/// Audio is written to disk only when the user has opted in (see `AudioStore`);
/// with the setting off, nothing but text ever leaves this class. When it is on,
/// the same tap feeds both the analyzer and the file, so the timings on each
/// segment line up with the recording exactly.
@MainActor
final class LiveTranscriber {
    struct TranscriberError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Invoked on the main actor whenever the transcript changes. `finalized` is
    /// committed text that will never change; `volatile` is the in-progress tail
    /// still being refined by the recognizer.
    var onUpdate: ((_ finalized: String, _ volatile: String) -> Void)?

    /// Invoked on the main actor for each captured audio buffer with a normalized
    /// loudness level in 0...1, for driving a live waveform.
    var onAudioLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var interruptionObserver: NSObjectProtocol?
    private var audioFile: AVAudioFile?
    private var audioURL: URL?

    private(set) var finalizedText = ""
    /// Finalized speech with its position in the audio. Empty until the first
    /// result lands; kept alongside `finalizedText` rather than replacing it so
    /// nothing downstream has to change to keep working.
    private(set) var segments: [TranscriptSegment] = []
    private var volatileText = ""
    private var isRunning = false

    /// BCP-47 locales this device can transcribe on-device. Empty on the Simulator
    /// (no speech models); populated on a real iOS 26 device. Only these should be
    /// offered to the user for selection.
    static func supportedLanguages() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    // MARK: - Lifecycle

    /// Requests permission, ensures the on-device language model is installed,
    /// then starts capturing and transcribing. Throws before any state changes if
    /// permission is denied or the model can't be prepared.
    ///
    /// - Parameters:
    ///   - languageCode: BCP-47 identifier to transcribe in. When nil, the
    ///     device's current language is used (falling back to en-US).
    ///   - audioURL: where to write the recording. Nil means don't keep audio,
    ///     which is the default and what the app did exclusively until now.
    func start(languageCode: String? = nil, audioURL: URL? = nil) async throws {
        guard !isRunning else { return }
        finalizedText = ""
        volatileText = ""
        segments = []
        self.audioURL = audioURL

        try await requestAuthorization()

        // Language precedence when nothing is explicitly chosen:
        //   1. an explicit selection (from the picker next to Record),
        //   2. otherwise the iPhone's language — if it's supported on-device,
        //   3. otherwise English.
        let locale: Locale
        if let languageCode, !languageCode.isEmpty {
            locale = Locale(identifier: languageCode)
        } else if let deviceLanguage = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
            locale = deviceLanguage
        } else {
            locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
                ?? Locale(identifier: "en-US")
        }
        // `.audioTimeRange` is what makes every downstream feature possible —
        // synced playback, pause-based paragraphs, timestamps. It costs nothing
        // to request and cannot be recovered for recordings made without it.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        try await ensureModelInstalled(for: transcriber, locale: locale)

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputBuilder = continuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let piece = String(result.text.characters)
                    self.ingest(piece, isFinal: result.isFinal, range: result.range)
                }
            } catch {
                // Stream ended or the recognizer failed; whatever was finalized is kept.
            }
        }

        try await analyzer.start(inputSequence: stream)
        try configureAudioSessionAndEngine()
        registerInterruptionHandling()
        isRunning = true
    }

    /// Stops capture, flushes any pending recognition, and returns the full
    /// finalized transcript.
    @discardableResult
    func finish() async -> String {
        guard isRunning else { return finalizedText }
        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Releasing the file closes it and writes the AAC trailer; until that
        // happens the .m4a on disk is unplayable.
        audioFile = nil
        inputBuilder?.finish()
        inputBuilder = nil

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil

        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        analyzer = nil
        transcriber = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return finalizedText
    }

    /// Stops and discards everything (used when the user trashes a recording).
    func cancel() async {
        _ = await finish()
        finalizedText = ""
        volatileText = ""
        segments = []
        // A discarded recording should leave no audio behind.
        if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        audioURL = nil
    }

    // MARK: - Results

    private func ingest(_ piece: String, isFinal: Bool, range: CMTimeRange) {
        if isFinal {
            let clean = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                finalizedText += finalizedText.isEmpty ? clean : " " + clean

                let start = CMTimeGetSeconds(range.start)
                let end = CMTimeGetSeconds(range.end)
                // Guard against a non-numeric CMTime (an indefinite range) turning
                // into a NaN that would poison every later seek and comparison.
                if start.isFinite, end.isFinite, end >= start {
                    segments.append(TranscriptSegment(start: start, end: end, text: clean))
                }
            }
            volatileText = ""
        } else {
            volatileText = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        onUpdate?(finalizedText, volatileText)
    }

    // MARK: - Permissions & model

    private func requestAuthorization() async throws {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            throw TranscriberError(message: "Speech recognition permission is required to transcribe.")
        }

        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else {
            throw TranscriberError(message: "Microphone access is required to record.")
        }
    }

    /// Prepares the on-device language model for the transcriber's locale. The
    /// locale must be *reserved* before its asset status can be queried, then the
    /// model is downloaded the first time it's needed (network only for that
    /// one-time install).
    private func ensureModelInstalled(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let wanted = locale.identifier(.bcp47)

        let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
        guard supported.contains(wanted) else {
            throw TranscriberError(message: "On-device transcription isn't available for \(locale.identifier).")
        }

        // Reserve (subscribe to) the locale so its asset status can be checked and
        // the model kept installed.
        _ = try? await AssetInventory.reserve(locale: locale)

        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        if installed.contains(wanted) { return }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    // MARK: - Audio engine

    private func configureAudioSessionAndEngine() throws {
        let session = AVAudioSession.sharedInstance()
        // `.playAndRecord` + the `audio` background mode keeps capture alive while
        // the phone is locked or the app is backgrounded. `.spokenAudio` tunes the
        // input for speech.
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        if let analyzerFormat {
            converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
        }

        // AAC at 32 kbps is transparent enough for speech and lands around 15 MB
        // an hour — a semester of lectures rather than a full iCloud account. The
        // sample rate and channel count mirror the tap so the file's processing
        // format matches the buffers exactly and no second conversion is needed.
        if let audioURL {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVEncoderBitRateKey: 32_000,
            ]
            // A failure here must not stop the recording: the transcript is the
            // thing that matters, audio is the bonus.
            audioFile = try? AVAudioFile(forWriting: audioURL, settings: settings)
            if audioFile == nil { self.audioURL = nil }
        }

        // Capture locals so the realtime audio thread never touches main-actor state.
        let converter = self.converter
        let analyzerFormat = self.analyzerFormat
        let audioFile = self.audioFile
        guard let builder = inputBuilder else { return }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            let outBuffer = Self.convert(buffer, using: converter, to: analyzerFormat) ?? buffer
            builder.yield(AnalyzerInput(buffer: outBuffer))

            // Written from the same buffer the analyzer sees, so segment timings
            // and the file's timeline are the same clock.
            try? audioFile?.write(from: buffer)

            let level = Self.rmsLevel(buffer)
            Task { @MainActor in self?.onAudioLevel?(level) }
        }

        engine.prepare()
        try engine.start()
    }

    /// Resamples a mic buffer into the format the analyzer expects.
    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter?,
        to analyzerFormat: AVAudioFormat?
    ) -> AVAudioPCMBuffer? {
        guard let converter, let analyzerFormat else { return nil }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else {
            return nil
        }

        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }

    /// Normalized loudness (0...1) of a mic buffer, mapped from dBFS so the
    /// waveform tracks perceived volume rather than raw linear amplitude.
    private nonisolated static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(buffer.frameLength))
        guard rms > 0 else { return 0 }

        // Map roughly -50 dBFS (near-silence) ... 0 dBFS (max) onto 0 ... 1.
        let db = 20 * log10(Double(rms))
        let normalized = (db + 50) / 50
        return Float(max(0, min(1, normalized)))
    }

    // MARK: - Interruptions

    private func registerInterruptionHandling() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            // A phone call / Siri took the mic. Pause capture — finalized text is
            // already safe. The stream stays open so we can resume seamlessly.
            engine.pause()
        case .ended:
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
        @unknown default:
            break
        }
    }
}
