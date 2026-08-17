# recap — implementation plan

Working document for the migration off Supabase and Next.js. Written 2026-07-28.
Read this together with `CLAUDE.md`, which describes the architecture as it
exists today — parts of it become wrong as these phases land, and updating it is
a task in Phase 2.

---

## The decisions, and why

**recap is an iOS app. It should have no infrastructure until it earns some.**

| Decision | Reason |
|---|---|
| Drop the Next.js app | It was scaffolding. The app can call Anthropic directly with the user's own key. |
| Drop Supabase | Free tier pauses after 7 days of inactivity, which would show users a broken app. Fixing it means Pro at $25/mo — $300/yr before any revenue. |
| Data → SwiftData + CloudKit | Free forever, never sleeps, survives a lost phone, syncs across the user's devices, no accounts to run. |
| Audio → device or iCloud, off by default | Zero storage cost, and the app's long-standing promise is that audio is never kept unless asked for. |
| BYOK, and only BYOK | The user's key calls Anthropic directly from the app. No server can leak what it never holds — and it costs the developer nothing, so there is nothing to charge for. |
| No paywall at all | Running the app costs nothing. Monetisation was designed in full and deliberately dropped; see "Deliberately not doing". |

**One-way door acknowledged:** CloudKit is Apple-only. No web version, no easy
Android. This was accepted deliberately.

**The app has no backend, no accounts, and no revenue model.** Every future
proposal should be measured against that — it is the point, not a stepping stone.

---

## Apple Developer Program

Enrolment ($99/yr) is **required before Phase 2**. A free Apple ID can run the
Simulator, build to the developer's own iPhone, and use local SwiftData — but
cannot sign the CloudKit or iCloud entitlements that Phases 2 and 3 depend on,
and cannot use TestFlight or the App Store.

Two further reasons not to defer it: live transcription cannot be tested in the
Simulator at all, so all real testing is on a device, and free provisioning
profiles expire every 7 days.

Phase 1 needs no entitlements and can proceed on a free account while enrolment
processes.

---

## Current state

All of the following is **implemented and compiling** but uncommitted, and
predates the decisions above. It all survives the migration.

- **BYOK key security.** `AnthropicKeyStore` holds the user's Anthropic key in
  the device Keychain (`WhenUnlockedThisDeviceOnly` — not in iCloud, not in
  backups), scoped by user id, cleared on sign-out. The app can no longer read
  the key back for display; Settings shows only Set / Not set. It is attached to
  outbound requests by `attachUserKeyIfPresent` in
  `Core/Networking/UserAPIKeyHeader.swift` so no call site can forget it.
- **Library search** (`Core/Search/LibrarySearch.swift`) across titles,
  transcripts, summaries, personal notes, speaker and event fields.
  Case/diacritic-insensitive, multi-word AND, with highlighted match snippets.
- **Export tabs** on recordings and projects (`Core/Export/MarkdownExport.swift`,
  `Features/Export/ExportTabView.swift`). Markdown out via share sheet or copy.
- **Timed transcripts.** `LiveTranscriber` requests `.audioTimeRange`; every
  finalized phrase becomes a `TranscriptSegment` (start/end/text). Stored in
  `notes.transcript_segments`. `notes.transcript` still holds the flat text and
  remains the source of truth for search, export and summaries.
- **Audio capture + synced playback.** `AudioStore` (off / phone / iCloud,
  default off, migrates on switch), `TranscriptPlayer`, and
  `Features/NoteDetail/SyncedTranscriptView.swift` — player pinned above a
  transcript that breaks into paragraphs at real pauses, highlights the phrase
  being spoken, auto-scrolls, and seeks on tap. "Delete audio" removes only the
  audio file and keeps everything else, behind a confirmation.
- **iCloud entitlement** written and then **commented out** in `project.yml`,
  because a free personal team cannot sign iCloud entitlements and leaving it in
  breaks device builds. Uncommenting it plus registering the container is all of
  Phase 3. Audio saving to the device works today with no entitlement at all.

### Database migrations

`supabase/migrations/` holds three files. Two are obsolete the moment Phase 2
lands, but should still be run now so the app keeps working in the meantime:

- `20260728000000_user_settings_rls.sql` — row-level security. Run if not already.
- `20260728000100_drop_stored_anthropic_key.sql` — drops the plaintext key column.
- `20260728000200_notes_transcript_segments.sql` — adds `transcript_segments`.

---

## Phase 1 — DONE (2026-07-28)

The app no longer talks to any server of ours. `AnthropicClient` posts to
`api.anthropic.com` with the key from the Keychain; `SummaryClient` and
`ProjectSummaryClient` own their prompts; project summaries are assembled on
device from the notes the app already has. `API_HOST` is gone from `AppConfig`,
`project.yml` and `Secrets.xcconfig`, and `UserAPIKeyHeader.swift` is deleted.
**The Vercel project can be deleted.**

Also landed since the plan was written: timestamps in exports, retroactive
sentence-based paragraphs for untimed transcripts, "## Action items" in both
summary prompts, and audio-file import (`AudioFileTranscriber`,
`AudioImportManager`, `Features/Import/`).

<details>
<summary>Original Phase 1 steps, for reference</summary>

### Phase 1 — Call Anthropic directly, delete the Next.js dependency

**Goal:** summaries work with no server. Roughly half a day.

1. Rewrite `Core/Networking/SummaryClient.swift` to POST
   `https://api.anthropic.com/v1/messages` directly.
   - Headers: `x-api-key: <key from AnthropicKeyStore>`,
     `anthropic-version: 2023-06-01`, `content-type: application/json`.
   - Model: `claude-sonnet-5`. Ask for a JSON object with `title`, `summary`,
     and `category` (one of `talk` / `training` / `panel`) so the existing
     `SummaryClient.Result` shape survives unchanged.
   - Port the prompt from the Next.js `/api/summarise` route if it still exists;
     otherwise write a fresh one.
2. Rewrite `Core/Networking/ProjectSummaryClient.swift` the same way. The
   prompt is now assembled **on device**: fetch the project's notes, concatenate
   their titles and summaries (falling back to transcripts), and send that.
3. When no key is stored, surface a clear, actionable error pointing at
   Settings — not a raw 401.
4. Delete `API_HOST` from `Core/Networking/AppConfig.swift`, `project.yml`, and
   `Recap/Resources/Secrets.xcconfig`. `AppConfig` currently `fatalError`s when
   it is missing, so this must be removed, not just left unset.
5. `attachUserKeyIfPresent` becomes the mandatory path rather than an optional
   one — without a key there is nothing to call. Adjust or inline it.

**Do not** add a fallback to a hardcoded platform key. There is no platform key,
and one would never live in the app binary.

</details>

---

## Phase 2 — Replace Supabase with SwiftData + CloudKit

**Goal:** zero infrastructure, zero cost, nothing to reactivate. Two to three days.

1. **Define SwiftData models** mirroring `Note`, `Project`, `PersonalNote`.
   CloudKit constraints: every property needs a default value or must be
   optional, no unique constraints, and all relationships must be optional.
   Keep `TranscriptSegment` as a `Codable` value stored on the note.
2. **Rewrite `StorageService`** against SwiftData, keeping the existing function
   names and signatures. All 33 call sites go through this one seam — if the
   signatures hold, the feature screens barely change. Cancellation handling
   (`error.isCancellation`) becomes unnecessary and can go.
3. **Configure the container** with `cloudKitDatabase: .private`, and add the
   CloudKit entitlement alongside the existing iCloud Documents one.
4. **Remove the account layer.** Delete `AuthManager`, `SignInView`,
   `SupabaseService`, and the auth switch in `ContentView` — the app opens
   straight into `AppShellView`. Remove the Supabase SPM dependency from
   `project.yml`.
5. **Simplify recording durability.** `PendingNoteStore`'s upload-queue role
   disappears: writes are local and immediate, and CloudKit syncs in the
   background. Keep only the crash-recovery behaviour — on launch, any note
   still marked in-progress is treated as finished. Drop the `NWPathMonitor`
   reconnect retry and the `didBecomeActive` retry in `RecordingManager`.
6. **Re-scope the Keychain key.** `AnthropicKeyStore` currently keys the item by
   Supabase user id via `StorageService.currentUserId()`. With no accounts, use
   a fixed account string instead.
7. **Delete `supabase/`** and the `user_settings` table concept entirely.
8. **Update `CLAUDE.md`** — the Architecture, Auth gate, Build & run and
   Database sections all become wrong.

**Existing data:** decided — **abandon it.** The only recordings in Supabase are
the developer's own test data. No export, no importer, no migration path. Delete
the Supabase project once Phase 2 is verified on a device.

---

## Phase 3 — Finish the iCloud audio story

1. Apple Developer portal → Identifiers → **iCloud Containers** → register
   `iCloud.com.jonchambers.recap`.
2. Open the App ID for `com.jonchambers.recap`, enable **iCloud**, tick that
   container.
3. Let Xcode refresh the provisioning profile.

A container identifier is **per-app, not per-user**: register it once and Apple
gives every Apple Account its own isolated private copy. The developer has no
access to any user's container contents.

---

## Deliberately not doing

Monetisation was designed in detail and then dropped, because with BYOK the app
costs the developer nothing to run. **Do not reintroduce any of this without
being asked.** Recorded only so the reasoning isn't rediscovered from scratch:

- **Credits** would require a backend — a platform Anthropic key can't ship in an
  app binary, and a balance must be metered where the user can't reach it. That
  means Cloudflare Workers + D1 (free tier never sleeps, unlike Supabase's) plus
  Sign in with Apple for identity. The design that was worked out: flat
  per-action pricing on a length tier rather than token metering, credits shown
  instead of currency, automatic refunds on failed generation, BYOK users never
  charged.
- **A one-time Pro unlock** would need no backend at all — StoreKit handles
  non-consumable purchases on-device. The free/paid line, if ever wanted, was:
  capture stays free (unlimited recording, transcription, transcripts), and
  everything downstream is paid (unlimited projects, export, library-wide search).
- Apple takes 15% under the Small Business Program. Selling via the web saves
  only ~50¢–$1 per pack once tax handling is counted — never worth building first.

---

## Parked

- **Speaker diarization.** No API exists in iOS 26. Cheapest useful version is
  asking the model to attribute speakers in the summary; next is manual speaker
  marking using the segment timings. On-device ML diarization is weeks of work
  and degrades badly in exactly the noisy, reverberant rooms this app targets.
- **Retroactive paragraph formatting.** Recordings made before timing capture
  shipped have no segments and render as one block. A sentence-tokeniser
  fallback in `SyncedTranscriptView` would fix them without any data change.
- **Timestamps in exports.** `MarkdownExport` ignores segment timings; adding
  `[00:12:34]` markers would make exported transcripts far more useful.

---

## Standing constraints

- Use the design system: `Spacing`/`Radius`, `AppColors`, `.appTextStyle(_:)`,
  `AppCard`/`FilterChip`/`AppChip`/`SegmentedChipBar`/`EmptyStateView`, the
  `.appPrimary`/`.appSecondary`/`.appDestructive`/`.appIcon` button styles.
  Never raw values.
- Dark mode only — `AppColors` tokens are single values.
- New Swift files must be registered: re-run `xcodegen generate`.
- Live transcription cannot be verified in the Simulator — no speech models.
  Compile-check with
  `-destination 'generic/platform=iOS Simulator'`; real verification needs a device.
- Audio is never kept unless the user opted in. Deleting a note's audio must
  never touch the transcript, notes or summary.
