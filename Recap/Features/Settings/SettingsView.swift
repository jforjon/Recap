import SwiftUI

struct SettingsView: View {
    let authManager: AuthManager

    @State private var email = ""
    @State private var anthropicKey = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    @State private var supportedLanguages: [Locale] = []
    @State private var selectedLanguages: [String] = []
    @State private var defaultLanguage = ""

    var body: some View {
        Form {
            Section("Account") {
                Text(email)
                    .appTextStyle(.body)
                    .foregroundStyle(AppColors.neutral600)
            }

            Section("Anthropic API key") {
                AppSecureField(title: "Anthropic (Claude)", text: $anthropicKey)

                Button(isSaving ? "Saving…" : "Save key") {
                    Task { await saveKeys() }
                }
                .buttonStyle(.appPrimary)
                .disabled(isSaving)

                if let savedMessage {
                    Text(savedMessage)
                        .foregroundStyle(AppColors.success500)
                        .appTextStyle(.small)
                }
            }

            spokenLanguagesSection

            Section {
                Button("Sign out", role: .destructive) {
                    Task { try? await authManager.signOut() }
                }
                .buttonStyle(.appSecondary)
            }
        }
        .recapBackground()
        .navigationTitle("Settings")
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Spoken languages

    @ViewBuilder
    private var spokenLanguagesSection: some View {
        // Only render when the device actually supports on-device transcription and
        // reports installable languages — otherwise there's nothing to list.
        if !supportedLanguages.isEmpty {
            Section("Spoken languages") {
                Text("Add the languages you record in. The default shows next to Record. Leave empty to just use your device language.")
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.neutral500)

                ForEach(supportedLanguages, id: \.identifier) { locale in
                    let code = locale.identifier(.bcp47)
                    Button {
                        toggleLanguage(code)
                    } label: {
                        HStack {
                            Text(displayName(code))
                                .foregroundStyle(AppColors.neutral800)
                            Spacer()
                            if selectedLanguages.contains(code) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.categoryPanel)
                            }
                        }
                    }
                }

                if !selectedLanguages.isEmpty {
                    Picker("Default", selection: $defaultLanguage) {
                        ForEach(selectedLanguages, id: \.self) { code in
                            Text(displayName(code)).tag(code)
                        }
                    }
                    .onChange(of: defaultLanguage) { _, newValue in
                        SpokenLanguageStore.defaultLanguage = newValue.isEmpty ? nil : newValue
                    }
                }
            }
        }
    }

    private func toggleLanguage(_ code: String) {
        SpokenLanguageStore.toggle(code)
        selectedLanguages = SpokenLanguageStore.selected
        defaultLanguage = SpokenLanguageStore.defaultLanguage ?? ""
    }

    private func displayName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    // MARK: - Loading & saving

    private func load() async {
        if case let .signedIn(_, userEmail) = authManager.state {
            email = userEmail ?? ""
        }

        supportedLanguages = (await LiveTranscriber.supportedLanguages())
            .sorted { displayName($0.identifier(.bcp47)) < displayName($1.identifier(.bcp47)) }
        selectedLanguages = SpokenLanguageStore.selected
        defaultLanguage = SpokenLanguageStore.defaultLanguage ?? ""

        do {
            let settings = try await StorageService.getUserSettings()
            anthropicKey = settings.anthropicApiKey ?? ""
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func saveKeys() async {
        isSaving = true
        savedMessage = nil
        defer { isSaving = false }
        do {
            try await StorageService.saveUserSettings(
                UserSettings(anthropicApiKey: anthropicKey.trimmingCharacters(in: .whitespaces))
            )
            savedMessage = "Saved"
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
