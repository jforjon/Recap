import SwiftUI

struct SettingsView: View {
    let authManager: AuthManager

    @State private var email = ""
    @State private var openaiKey = ""
    @State private var anthropicKey = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Text(email)
                        .foregroundStyle(.secondary)
                }

                Section("API keys") {
                    AppSecureField(title: "OpenAI (Whisper)", text: $openaiKey)
                    AppSecureField(title: "Anthropic (Claude)", text: $anthropicKey)

                    Button(isSaving ? "Saving…" : "Save keys") {
                        Task { await saveKeys() }
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(isSaving)

                    if let savedMessage {
                        Text(savedMessage).foregroundStyle(.green).font(.footnote)
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { try? await authManager.signOut() }
                    }
                    .buttonStyle(.appSecondary)
                }
            }
            .navigationTitle("Settings")
            .task { await load() }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func load() async {
        if case let .signedIn(_, userEmail) = authManager.state {
            email = userEmail ?? ""
        }
        do {
            let settings = try await StorageService.getUserSettings()
            openaiKey = settings.openaiApiKey ?? ""
            anthropicKey = settings.anthropicApiKey ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveKeys() async {
        isSaving = true
        savedMessage = nil
        defer { isSaving = false }
        do {
            try await StorageService.saveUserSettings(
                UserSettings(
                    openaiApiKey: openaiKey.trimmingCharacters(in: .whitespaces),
                    anthropicApiKey: anthropicKey.trimmingCharacters(in: .whitespaces)
                )
            )
            savedMessage = "Saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
