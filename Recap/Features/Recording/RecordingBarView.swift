import SwiftUI

/// The "Start recording" bar pinned under the Library and project screens.
///
/// Only the idle state lives here: once capture begins, `RecordingSessionView`
/// takes over the whole screen, and this collapses to nothing behind it.
struct RecordingBarView: View {
    let recordingManager: RecordingManager
    /// When set, recordings started from this bar are filed under the project;
    /// `nil` (the Library bar) starts a standalone recording.
    var projectId: UUID? = nil

    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var chosenLanguage = ""

    private var languages: SpokenLanguageStore { SpokenLanguageStore.shared }

    var body: some View {
        Group {
            if recordingManager.phase == .idle {
                let options = languages.options
                HStack(spacing: Spacing.s3) {
                    // Shown whenever the device has any models at all. It used to
                    // appear only once languages had been shortlisted in Settings,
                    // which meant the language of a recording couldn't be chosen
                    // without first knowing there was a setting for it.
                    if !options.isEmpty {
                        languageMenu(options)
                    }
                    Button(isStarting ? "Starting…" : "Start recording") {
                        Task { await start(language: effectiveLanguage) }
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(isStarting)
                }
            }
        }
        .padding(.horizontal, Spacing.s4)
        .task { await languages.loadAvailable() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Language selection

    @ViewBuilder
    private func languageMenu(_ options: [String]) -> some View {
        let current = effectiveLanguage
        Menu {
            ForEach(options, id: \.self) { code in
                Button {
                    chosenLanguage = code
                } label: {
                    if code == current {
                        Label(SpokenLanguageStore.displayName(code), systemImage: "checkmark")
                    } else {
                        Text(SpokenLanguageStore.displayName(code))
                    }
                }
                .tint(AppColors.textPrimary)
            }
        } label: {
            // Geometry mirrors the pill button styles (44pt frame + s2 vertical
            // padding = 60pt) so the selector lines up with "Start recording".
            HStack(spacing: Spacing.s1 + 2) {
                Image(systemName: "globe")
                    .font(.system(size: 15))
                Text(shortName(current ?? ""))
            }
            .appTextStyle(.bodyMedium)
            .foregroundStyle(AppColors.textPrimary)
            .frame(height: 44)
            .padding(.vertical, Spacing.s2)
            .padding(.horizontal, Spacing.s4)
            .background(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .accessibilityLabel("Recording language")
    }

    /// The language picked in the moment if it's still on offer, otherwise the
    /// store's default — the one set in Settings, else English.
    private var effectiveLanguage: String? {
        if languages.options.contains(chosenLanguage) { return chosenLanguage }
        return languages.defaultLanguage
    }

    private func shortName(_ code: String) -> String {
        Locale(identifier: code).language.languageCode?.identifier.uppercased() ?? code.uppercased()
    }

    private func start(language: String?) async {
        isStarting = true
        defer { isStarting = false }
        do {
            try await recordingManager.startRecording(projectId: projectId, language: language)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
