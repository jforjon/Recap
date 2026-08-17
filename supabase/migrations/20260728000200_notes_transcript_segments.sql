-- Timed transcript segments, for synchronised playback.
--
-- Every finalized result from iOS 26's SpeechTranscriber carries a CMTimeRange
-- saying where in the audio it was spoken. The app now keeps that instead of
-- discarding it, which is what lets the transcript highlight and scroll while a
-- recording plays back — and what gives it real paragraph breaks, since a long
-- gap between segments is a genuine pause rather than a guess.
--
-- Shape: [{"start": 12.4, "end": 15.1, "text": "..."}, ...], seconds from the
-- start of the recording.
--
-- Additive and nullable on purpose. notes.transcript stays the source of truth
-- for search, export and summaries, so nothing that exists today changes
-- behaviour, and recordings made before this shipped simply have no segments and
-- render the way they always have.
--
-- Safe to run before shipping the app build; the column is just unused until then.

begin;

alter table public.notes
  add column if not exists transcript_segments jsonb;

commit;
