# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`recap` — a SwiftUI iOS 26 app for recording talks, panels and trainings, transcribing them **on device**, and filing them under projects. Backend is Supabase (auth + Postgres). AI summaries are produced by a separate Next.js web app's API routes, not in the app.

The iOS code is a deliberate port of that web app: `StorageService` mirrors `app/lib/storage.ts` function-for-function, `SupabaseService` mirrors `app/lib/supabase.ts`, `SummaryClient` mirrors `app/lib/claude.ts`, and the design tokens are a 1:1 port of the web `tokens.css` / `globals.css` scales. When changing data access or tokens, keep that parity — the naming is intentional, not accidental.

## Build & run

The Xcode project is **generated and gitignored**. `project.yml` (XcodeGen) is the source of truth for the target, Info.plist properties, and the Supabase SPM dependency.

```bash
xcodegen generate
```

```bash
xcodebuild -project Recap.xcodeproj -scheme Recap -configuration Debug -destination 'id=<SIMULATOR_UDID>' -derivedDataPath build/DD build
```

```bash
xcrun simctl list devices available
```

- **Any new Swift file must be registered before it builds.** Re-run `xcodegen generate` (it globs the whole `Recap/` path), or hand-add the `PBXFileReference` + `PBXBuildFile` + group + Sources phase entries to `Recap.xcodeproj/project.pbxproj`. A file that only exists on disk is silently not compiled.
- `Recap/Resources/Secrets.xcconfig` is required and gitignored. It must define `SUPABASE_PROJECT_REF` and `SUPABASE_ANON_KEY`; these flow through Info.plist into `AppConfig`, which `fatalError`s at launch if either is missing or empty. (`API_HOST` is deliberately gone — the app calls Anthropic directly now.)
- **Code signing belongs in `project.yml`, never in Xcode's Signing & Capabilities editor.** The `.xcodeproj` is regenerated, so a team set through the UI survives only until the next `xcodegen generate`. Because the Simulator doesn't sign, losing it breaks *device* builds only — `Signing for "Recap" requires a development team` — which reads like a device problem and isn't. `DEVELOPMENT_TEAM` and `CODE_SIGN_STYLE` are pinned in `project.yml` for that reason.
- There is no test target and no tests in this repo.
- **The Simulator has no on-device speech models**, so `SpeechTranscriber.supportedLocales` is empty there and recording fails. Live transcription can only be verified on a real iOS 26 device.

## Database changes

SQL lives in `supabase/migrations/` and is applied manually against the Supabase project — there is no migration runner wired into the app. Migrations are written to be idempotent and must be applied *before* shipping an app build that depends on the new shape.

## Architecture

Three layers under `Recap/`: `Core/` (no SwiftUI), `DesignSystem/` (reusable views + tokens), `Features/` (screens).

**Auth gate.** `RecapApp` → `ContentView` switches on `AuthManager.state` (`.loading` / `.signedOut` / `.signedIn`), which is driven by a long-lived task over `authStateChanges`. `SignInView` and `AppShellView` are the two branches; there is no other routing above them.

**Navigation.** `AppShellView` renders two different trees off the same `AppNavigationModel` state: a `NavigationSplitView` (iPad/Mac) and, on compact width, a `NavigationStack` where Library is the root and projects/notes push on top. The compact path adapts by observing `nav.sidebarSelection` / `nav.detailSelection`, resetting them to `nil` and appending to `path` — that reset is what lets the same row be re-tapped. `nav.projectsVersion` is a counter bumped on project create/delete so the sidebar refreshes without callback plumbing.

**Recording is the durability story.** `LiveTranscriber` captures the mic via `AVAudioEngine` and streams into iOS 26's `SpeechAnalyzer`/`SpeechTranscriber` — fully on device, no network, and **audio is never written to disk**. It emits `(finalized, volatile)`; only finalized text is persisted, since the volatile tail still changes. `RecordingManager` writes that text to `PendingNoteStore` (a lock-guarded JSON manifest in Documents) as it is spoken, then uploads to Supabase on stop. Failed or interrupted uploads stay queued and are retried on launch, on `NWPathMonitor` reconnect, and on `didBecomeActive`; a recording found still in `.recording` status at launch is treated as finished and uploaded. Notes are saved transcript-only — summaries are opt-in later.

**Summaries are remote.** `SummaryClient` / `ProjectSummaryClient` POST to `API_HOST`'s `/api/summarise` and `/api/projects/[id]/summary` with the Supabase access token as a bearer. The app never calls Anthropic directly; the `anthropic_api_key` in `user_settings` is stored for the web app's use.

**Personal notes** hang off *either* a project or a single recording (`PersonalNoteOwner`), enforced by a `num_nonnulls(project_id, note_id) = 1` check constraint. Encode payloads with optional `projectId`/`noteId` so the unused column is omitted from the insert rather than sent as null.

## Conventions

- **Cancellation is not failure.** SwiftUI restarting a `.task` surfaces `CancellationError`/`URLError.cancelled`. Always `if error.isCancellation { return }` before showing an error, and in `StorageService` let cancellations propagate instead of converting them into "not found".
- **Dark mode only.** The app pins `.preferredColorScheme(.dark)`, so `AppColors` tokens are single values, not light/dark pairs.
- **Use the design system, never raw values.** `Spacing`/`Radius` for geometry, `AppColors` for color, `.appTextStyle(_:)` for type, `AppCard`/`FilterChip`/`AppChip`/`SegmentedChipBar`/`EmptyStateView` for structure, the `.appPrimary`/`.appSecondary`/`.appDestructive`/`.appIcon` button styles for controls. Scrolling screens get `.recapBackground()`; list rows holding cards get `.recapCardRow()`. `AppColors.neutral*` is a back-compat remap onto the new roles — prefer the semantic names (`textPrimary`, `surface`, `separator`) in new code.
- Menu items use `AppMenuButton`, which pins tint to the label color — the app's amber accent otherwise leaves menu icons amber against white labels.
- Models are `Codable` with explicit snake_case `CodingKeys` matching Postgres columns. Partial updates take a `JSONObject` of only the changed keys, mirroring `Partial<T>` on the web side.
- Concurrency: `RecordingManager` and `LiveTranscriber` are `@MainActor`; state objects use `@Observable`. Audio-tap work is `nonisolated static` so the realtime thread never touches main-actor state.
