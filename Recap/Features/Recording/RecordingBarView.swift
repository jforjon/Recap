import SwiftUI

struct RecordingBarView: View {
    let recordingManager: RecordingManager

    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var chosenLanguage = ""

    var body: some View {
        Group {
            switch recordingManager.phase {
            case .idle:
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

            case .recording:
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    if !recordingManager.liveTranscript.isEmpty {
                        Text(recordingManager.liveTranscript)
                            .appTextStyle(.body)
                            .foregroundStyle(AppColors.neutral800)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: Spacing.s3) {
                        Button {
                            recordingManager.discardRecording()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.appIcon)

                        RecordingWaveformView(levels: recordingManager.audioLevels)

                        Text(formattedElapsed)
                            .appTextStyle(.mono)
                            .foregroundStyle(AppColors.neutral600)
                            .frame(minWidth: 36, alignment: .trailing)

                        Button {
                            recordingManager.stopRecording()
                        } label: {
                            Image(systemName: "arrow.up")
                                .fontWeight(.semibold)
                        }
                        .frame(width: 44, height: 44)
                        .background(AppColors.accent)
                        .foregroundStyle(AppColors.accentText)
                        .clipShape(Circle())
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s4)
                .background(
                    Color.clear.background(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
        .padding(.horizontal, Spacing.s4)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var formattedElapsed: String {
        let m = recordingManager.elapsed / 60
        let s = recordingManager.elapsed % 60
        return String(format: "%02d:%02d", m, s)
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
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text(shortName(current))
            }
            .appTextStyle(.mono)
            .foregroundStyle(AppColors.neutral700)
            .padding(.horizontal, Spacing.s3)
            .frame(height: 44)
            .background(AppColors.neutral200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
            try await recordingManager.startRecording(language: language)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
