import Foundation

/// One finalized run of speech, with where it sits in the audio measured in
/// seconds from the start of the recording.
///
/// `SpeechTranscriber` hands back a `CMTimeRange` with every finalized result;
/// we keep it instead of discarding it. That single fact is what makes playback
/// able to highlight the words being spoken — and it also gives the transcript
/// real paragraph breaks, since a long gap between one segment ending and the
/// next beginning is a genuine pause rather than a guess.
struct TranscriptSegment: Codable, Hashable, Identifiable {
    let start: Double
    let end: Double
    let text: String

    var id: Double { start }
}

extension Array where Element == TranscriptSegment {
    /// The flat transcript, joined the way it always was. `notes.transcript` still
    /// holds this so search, export and summaries keep working untouched.
    var plainText: String {
        map(\.text).joined(separator: " ")
    }

    /// The segment being spoken at `time`, for highlighting during playback.
    /// Returns the last segment that has started, so the highlight persists
    /// through the small gaps between segments instead of flickering off.
    func index(at time: Double) -> Int? {
        guard !isEmpty else { return nil }
        guard time >= self[0].start else { return nil }

        var low = 0
        var high = count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if self[mid].start <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// Groups segments into paragraphs, breaking wherever the speaker paused for
    /// longer than `pauseThreshold`. A slide change, a question landing, or a
    /// panellist handing over all show up as a gap of a second or more.
    func paragraphs(pauseThreshold: Double = 1.2) -> [[TranscriptSegment]] {
        guard !isEmpty else { return [] }

        var result: [[TranscriptSegment]] = []
        var current: [TranscriptSegment] = [self[0]]

        for segment in dropFirst() {
            let gap = segment.start - (current.last?.end ?? segment.start)
            // Very long paragraphs are hard to read even without a pause, so cap
            // them — a speaker in full flow would otherwise produce one huge block.
            let tooLong = current.reduce(0) { $0 + $1.text.count } > 700
            if gap >= pauseThreshold || tooLong {
                result.append(current)
                current = [segment]
            } else {
                current.append(segment)
            }
        }
        result.append(current)
        return result
    }
}
