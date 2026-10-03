# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`recap` — a SwiftUI iOS 26 app for recording talks, panels and trainings, transcribing them **on device**, and filing them under projects. There is **no backend and no accounts**: data is SwiftData synced through the user's private CloudKit database, and AI summaries call Anthropic directly with the user's own key (BYOK). See `PLAN.md` for why, and for what not to reintroduce.

The iOS code began as a port of a Next.js web app, and the naming still follows it: `StorageService` keeps `app/lib/storage.ts`'s function names and signatures, and the design tokens are a 1:1 port of the web `tokens.css` / `globals.css` scales. Keep that naming — `StorageService` is deliberately the single seam a future move back to a server would touch (see "Keeping a way back to a server" in `PLAN.md`).

## Build & run

The Xcode project is **generated and gitignored**. `project.yml` (XcodeGen) is the source of truth for the target, Info.plist properties and entitlements. There are no package dependencies.

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
- `Recap/Resources/Secrets.xcconfig` is required and gitignored. It defines `FEEDBACK_SCRIPT_ID` and `FEEDBACK_SECRET` for the feedback screen; both are optional at runtime (a missing endpoint disables that one screen). Nothing else is configured — there is no backend.
- **iCloud needs the paid team.** `project.yml` signs CloudKit + iCloud Documents entitlements for the container `iCloud.com.jonchambers.recap`, which must be registered in the developer portal and enabled on the App ID. If CloudKit can't be set up, `RecapStore` falls back to the same store file, local-only.
- **Code signing belongs in `project.yml`, never in Xcode's Signing & Capabilities editor.** The `.xcodeproj` is regenerated, so a team set through the UI survives only until the next `xcodegen generate`. Because the Simulator doesn't sign, losing it breaks *device* builds only — `Signing for "Recap" requires a development team` — which reads like a device problem and isn't. `DEVELOPMENT_TEAM` and `CODE_SIGN_STYLE` are pinned in `project.yml` for that reason.
- There is no test target and no tests in this repo.
- **The Simulator has no on-device speech models**, so `SpeechTranscriber.supportedLocales` is empty there and recording fails. Live transcription can only be verified on a real iOS 26 device.

## Data model changes

The store is SwiftData (`Core/Storage/Records.swift`), mirrored to CloudKit. CloudKit's rules apply to every `@Model`: each attribute has a default or is optional, nothing is `.unique`, and there are no relationships — links are plain UUID attributes (`projectId`, `noteId`), and cascades are done by hand in `StorageService`. Once a schema has been deployed to the CloudKit production environment, changes must be **additive only** (new optional attributes or new models); never rename or delete an attribute.

## Architecture

Three layers under `Recap/`: `Core/` (no SwiftUI), `DesignSystem/` (reusable views + tokens), `Features/` (screens).

**No auth gate.** `RecapApp` → `ContentView` → `AppShellView`. There is no sign-in; the user's iCloud account is the only identity.

**Storage.** `RecapStore.container` is the one `ModelContainer` (CloudKit `.private`). Screens never touch SwiftData: they call `StorageService`, which opens a fresh `ModelContext` per call and converts `NoteRecord` / `ProjectRecord` / `PersonalNoteRecord` to the `Note` / `Project` / `PersonalNote` value types the views use. Those structs still carry `created_at` as an ISO string. CloudKit imports from other devices post `NSPersistentStoreRemoteChange`; `AppShellView` turns that into a `nav.projectsVersion` bump.

**Navigation.** `AppShellView` renders two different trees off the same `AppNavigationModel` state: a `NavigationSplitView` (iPad/Mac) and, on compact width, a `NavigationStack` where Library is the root and projects/notes push on top. The compact path adapts by observing `nav.sidebarSelection` / `nav.detailSelection`, resetting them to `nil` and appending to `path` — that reset is what lets the same row be re-tapped. `nav.projectsVersion` is a counter bumped on project create/delete so the sidebar refreshes without callback plumbing.

**Recording is the durability story.** `LiveTranscriber` captures the mic via `AVAudioEngine` and streams into iOS 26's `SpeechAnalyzer`/`SpeechTranscriber` — fully on device, no network, and **audio is never written to disk**. It emits `(finalized, volatile)`; only finalized text is persisted, since the volatile tail still changes. `RecordingManager` writes that text to `PendingNoteStore` (a lock-guarded JSON journal in Documents, deliberately outside SwiftData so half-finished recordings never sync) as it is spoken, then saves it to the store on stop under the same id it was captured with. A recording found in the journal at launch — the app was killed mid-capture or mid-save — is treated as finished and saved then; `saveNote` is idempotent on id, so that can't duplicate. Notes are saved transcript-only — summaries are opt-in later.

**Summaries are BYOK.** `SummaryClient` / `ProjectSummaryClient` call Anthropic directly through `AnthropicClient`, using the key `AnthropicKeyStore` keeps in the device Keychain (this-device-only, never synced). Project summaries are assembled on device from the project's notes.

**Personal notes** hang off *either* a project or a single recording (`PersonalNoteOwner`); `PersonalNoteRecord(owner:)` sets exactly one of `projectId`/`noteId`.

## Conventions

- **Cancellation is not failure.** SwiftUI restarting a `.task` surfaces `CancellationError`/`URLError.cancelled`. Always `if error.isCancellation { return }` before showing an error. (Storage is local now and doesn't cancel, but every Anthropic call can.)
- **Dark mode only.** The app pins `.preferredColorScheme(.dark)`, so `AppColors` tokens are single values, not light/dark pairs.
- **Use the design system, never raw values.** `Spacing`/`Radius` for geometry, `AppColors` for color, `.appTextStyle(_:)` for type, `AppCard`/`FilterChip`/`AppChip`/`SegmentedChipBar`/`EmptyStateView` for structure, the `.appPrimary`/`.appSecondary`/`.appDestructive`/`.appIcon` button styles for controls. Scrolling screens get `.recapBackground()`; list rows holding cards get `.recapCardRow()`. `AppColors` has two tiers and screens use only the second: `neutral0…1000` / `blue0…900` are the **palette** (position on an OKLCH lightness ladder, no meaning), and `background` / `surface` / `textSecondary` / `accent` etc. are **roles** aliased onto those steps. Never reference a ramp step from a screen, and never reach for an ad-hoc `.opacity()` to invent a grey — pick the role whose step you want. The hairlines (`separator`, `separatorStrong`, `chipFill`, `chipStroke`) are the deliberate exception: they stay white-at-low-alpha so they read on any surface.
- Menu items use `AppMenuButton`, which pins tint to the label color — the app's amber accent otherwise leaves menu icons amber against white labels.
- Value types keep explicit snake_case `CodingKeys` matching the old Postgres columns, so the shapes still line up with a server. Partial updates take a `JSONObject` (`[String: JSONValue]`) of only the changed keys, keyed by those column names and applied by `NoteRecord.apply` / `ProjectRecord.apply`, which throw on an unknown key.
- Concurrency: `RecordingManager` and `LiveTranscriber` are `@MainActor`; state objects use `@Observable`. Audio-tap work is `nonisolated static` so the realtime thread never touches main-actor state.
