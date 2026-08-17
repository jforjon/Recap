import SwiftUI
import UniformTypeIdentifiers

/// Attaches the audio-import flow — file picker, the keep-the-audio question,
/// and error reporting — to a screen, driven by a binding the caller owns.
///
/// Split from its trigger on purpose: the import action lives inside a menu, and
/// a menu item is torn down the moment it's tapped, taking any `.fileImporter`
/// attached to it with it. The machinery has to hang off a view that stays.
struct AudioImporterModifier: ViewModifier {
    @Binding var isPresented: Bool
    let importManager: AudioImportManager
    /// nil imports unfiled into the Library.
    var projectId: UUID?

    @State private var pendingURL: URL?
    @State private var askAboutKeeping = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav, .aiff],
                allowsMultipleSelection: false
            ) { result in
                handlePicked(result)
            }
            // Only asked when the user's default is not to keep audio. Importing
            // is a deliberate act, so it's worth checking rather than silently
            // discarding a file they may have no other copy of — or silently
            // writing one they chose not to keep.
            .alert("Keep the audio?", isPresented: $askAboutKeeping) {
                Button("Keep it") { queue(keepAudio: true) }
                Button("Transcript only") { queue(keepAudio: false) }
                Button("Cancel", role: .cancel) { pendingURL = nil }
            } message: {
                Text("Your setting is not to save audio. Keeping this file lets you play it back with the transcript following along; transcript only uses no space.")
            }
            .alert("Import failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            guard AudioImportManager.isSupported(url) else {
                errorMessage = "That file type isn't supported. Try an m4a, mp3, wav or aiff file."
                return
            }
            pendingURL = url
            if AudioStore.isEnabled {
                queue(keepAudio: true)  // they already chose to keep audio
            } else {
                askAboutKeeping = true
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    private func queue(keepAudio: Bool) {
        guard let url = pendingURL else { return }
        pendingURL = nil
        do {
            try importManager.enqueue(
                pickedURL: url,
                projectId: projectId,
                // Same language resolution as the Record button.
                languageCode: SpokenLanguageStore.defaultLanguage,
                keepAudio: keepAudio
            )
        } catch {
            errorMessage = "That file couldn't be copied into recap: \(error.localizedDescription)"
        }
    }
}

extension View {
    func audioImporter(
        isPresented: Binding<Bool>,
        importManager: AudioImportManager,
        projectId: UUID? = nil
    ) -> some View {
        modifier(AudioImporterModifier(
            isPresented: isPresented,
            importManager: importManager,
            projectId: projectId
        ))
    }
}

/// Row shown while a file is being transcribed.
struct ImportProgressRow: View {
    let progress: AudioImportManager.Progress
    let onDismiss: () -> Void

    var body: some View {
        AppCard {
            HStack {
                AppChip(text: progress.failure == nil ? "Importing" : "Failed")
                Spacer()
                if progress.failure != nil {
                    Button("Dismiss", action: onDismiss)
                        .appTextStyle(.small)
                        .foregroundStyle(AppColors.accentGraphic)
                        .buttonStyle(.plain)
                }
            }
            Text(progress.title)
                .appTextStyle(.bodyMedium)
                .foregroundStyle(AppColors.neutral800)

            if let failure = progress.failure {
                Text(failure)
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.destructiveText)
            } else {
                ProgressView(value: progress.fraction)
                    .tint(AppColors.accentGraphic)
                Text("Transcribing on device — you can keep using recap.")
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.neutral500)
            }
        }
    }
}
