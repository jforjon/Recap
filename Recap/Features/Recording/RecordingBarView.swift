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

    var body: some View {
        Group {
            if recordingManager.phase == .idle {
                let languages = SpokenLanguageStore.selected
                HStack(spacing: Spacing.s3) {
                    if !languages.isEmpty {
                        languageMenu(languages)
                    }
                    Button(isStarting ? "Starting…" : "Start recording") {
                        let language = languages.isEmpty ? nil : effectiveLanguage(languages)
                        Task { await start(language: language) }
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(isStarting)
                }
            }
        }
        .padding(.horizontal, Spacing.s4)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Language selection

    @ViewBuilder
    private func languageMenu(_ languages: [String]) -> some View {
        let current = effectiveLanguage(languages)
        Menu {
            ForEach(languages, id: \.self) { code in
                Button {
                    chosenLanguage = code
                } label: {
                    if code == current {
                        Label(displayName(code), systemImage: "checkmark")
                    } else {
                        Text(displayName(code))
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
                Text(shortName(current))
            }
            .appTextStyle(.bodyMedium)
            .foregroundStyle(AppColors.textPrimary)
            .frame(height: 44)
            .padding(.vertical, Spacing.s2)
            .padding(.horizontal, Spacing.s4)
            .background(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
    }

    /// The chosen language if still valid, otherwise the settings default (or the
    /// first available), so the default is preselected.
    private func effectiveLanguage(_ languages: [String]) -> String {
        if languages.contains(chosenLanguage) { return chosenLanguage }
        return SpokenLanguageStore.defaultLanguage ?? languages.first ?? ""
    }

    private func displayName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
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
