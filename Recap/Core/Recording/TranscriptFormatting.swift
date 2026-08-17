import Foundation

/// `1:23` or `1:02:03` — a position inside a recording. Companion to
/// `formatShortDate`, which formats calendar dates.
func formatTimecode(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}

/// Paragraph-splitting for transcripts that have no timing data.
///
/// Recordings made before `audioTimeRange` capture shipped are a single
/// unbroken run of text, because every finalized phrase was joined to the last
/// with a space. They can never gain real timings, but iOS 26's transcriber
/// punctuates as it goes — so the sentence boundaries are already in there and
/// can be used to break the wall of text up.
///
/// This is a heuristic and reads slightly worse than the pause-based paragraphs
/// new recordings get, but it applies retroactively to the entire library with
/// no migration.
enum TranscriptFormatting {
    static func paragraphs(from text: String, sentencesPerParagraph: Int = 4) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // `.localized` so the tokeniser applies the right sentence rules for the
        // language — abbreviations and quotation conventions differ, and this app
        // transcribes in whatever the user picked.
        var sentences: [String] = []
        trimmed.enumerateSubstrings(
            in: trimmed.startIndex..<trimmed.endIndex,
            options: [.bySentences, .localized]
        ) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sentence.isEmpty {
                sentences.append(sentence)
            }
        }

        // A transcript with no punctuation at all yields one giant "sentence".
        // Nothing useful to do with it, so hand it back whole rather than
        // chopping mid-thought at an arbitrary character count.
        guard sentences.count > 1 else { return [trimmed] }

        return stride(from: 0, to: sentences.count, by: sentencesPerParagraph).map { start in
            sentences[start..<Swift.min(start + sentencesPerParagraph, sentences.count)]
                .joined(separator: " ")
        }
    }
}
