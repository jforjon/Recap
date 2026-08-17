import Foundation
import Supabase

/// Fills in what a recording can't know about itself at the moment it starts:
/// its title, and who was speaking.
///
/// A recording is named `Recording · Jul 28, 2:14 PM` the instant it starts,
/// because a title has to exist before there is any transcript to derive one
/// from — and because capture must never wait on the network. This upgrades that
/// placeholder afterwards, on a best-effort basis, and writes the speaker's own
/// introduction into `speaker_context` at the same time.
///
/// Every failure path is silent by design. No key, no signal, a transcript too
/// short to name: the note keeps its date title and an empty speaker, both of
/// which the user can fill in by hand at any time.
enum NoteEnricher {

    /// Placeholder titles look like "Recording · Jul 28, 2:14 PM".
    ///
    /// Matching on shape rather than storing a flag avoids a database column —
    /// and a migration now plus another when SwiftData lands — to guard against
    /// a user manually naming something in exactly the app's own default format.
    static func isPlaceholder(_ title: String) -> Bool {
        title.hasPrefix("Recording · ")
    }

    /// Fills whichever of `note`'s title and speaker context are still missing.
    /// Returns the updated note when it wrote something, nil when it left things
    /// alone or couldn't reach Anthropic.
    ///
    /// Anything the user typed themselves is left alone — this only ever fills
    /// blanks, so re-running it can't overwrite a hand-written speaker note.
    @discardableResult
    static func enrichIfNeeded(_ note: Note) async -> Note? {
        let needsTitle = isPlaceholder(note.title)
        let needsSpeaker = (note.speakerContext ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needsTitle || needsSpeaker else { return nil }

        let transcript = (note.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }

        // Checked before calling so a user without a key never pays the round
        // trip, and never sees an error for something they didn't ask for.
        guard (try? await AnthropicKeyStore.load()) != nil else { return nil }

        guard let details = try? await OpeningDetailsClient.generate(transcript: transcript) else {
            return nil
        }

        var fields: JSONObject = [:]
        if needsTitle, let title = details.title {
            fields["title"] = .string(title)
        }
        if needsSpeaker, let speaker = details.speakerContext {
            fields["speaker_context"] = .string(speaker)
        }
        guard !fields.isEmpty else { return nil }

        return try? await StorageService.updateNote(note.id, fields: fields)
    }
}
