import Foundation
@preconcurrency import AVFoundation
import Speech

/// Transcribes an existing audio file on device, producing the same timed
/// segments a live recording would.
///
/// `SpeechAnalyzer.analyzeSequence(from:)` reads a whole file rather than a live
/// microphone stream, so imported recordings get identical treatment to ones
/// captured in the app: pause-based paragraphs, synced playback, timestamps in
/// exports. Nothing is uploaded — this is the same on-device pipeline.
enum AudioFileTranscriber {
    struct TranscribeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Output {
        let segments: [TranscriptSegment]
        let transcript: String
        /// File length in seconds, used for the recording's duration.
        let duration: Double
    }

    /// - Parameters:
    ///   - url: an audio file the caller already has read access to.
    ///   - languageCode: BCP-47 identifier, or nil for the device language.
    ///   - onProgress: 0...1, reported as segments land. Called on an arbitrary
    ///     task context — hop to the main actor before touching UI state.
    static func transcribe(
        url: URL,
        languageCode: String?,
        onProgress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> Output {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw TranscribeError(message: "That file couldn't be opened as audio.")
        }

        let duration = Double(file.length) / file.fileFormat.sampleRate
        guard duration > 0 else {
            throw TranscribeError(message: "That file contains no audio.")
        }

        let locale = try await resolveLocale(languageCode)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        try await ensureModelInstalled(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Collect results concurrently with the analysis: `analyzeSequence` only
        // returns once the file has been consumed, and results stream throughout.
        let collector = Task { () -> [TranscriptSegment] in
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                let start = CMTimeGetSeconds(result.range.start)
                let end = CMTimeGetSeconds(result.range.end)
                guard start.isFinite, end.isFinite, end >= start else { continue }

                segments.append(TranscriptSegment(start: start, end: end, text: text))
                onProgress(min(end / duration, 1))
            }
            return segments
        }

        do {
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            throw TranscribeError(message: "Transcription failed partway through this file.")
        }

        let segments = (try? await collector.value) ?? []
        guard !segments.isEmpty else {
            throw TranscribeError(
                message: "No speech was found in that file. Check it isn't silent, and that the language matches."
            )
        }

        return Output(segments: segments, transcript: segments.plainText, duration: duration)
    }

    // MARK: - Model plumbing
    //
    // Mirrors LiveTranscriber's locale resolution and asset installation so an
    // imported file behaves identically to a live recording.

    private static func resolveLocale(_ languageCode: String?) async throws -> Locale {
        if let languageCode, !languageCode.isEmpty {
            return Locale(identifier: languageCode)
        }
        if let deviceLanguage = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
            return deviceLanguage
        }
        guard let fallback = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "en-US")
        ) else {
            throw TranscribeError(message: "No on-device transcription language is available.")
        }
        return fallback
    }

    private static func ensureModelInstalled(
        for transcriber: SpeechTranscriber,
        locale: Locale
    ) async throws {
        _ = try? await AssetInventory.reserve(locale: locale)
        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        if installed.contains(locale.identifier(.bcp47)) { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}
