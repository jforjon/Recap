import SwiftUI

/// The Anthropic key screen, ordered by what you came to do: remove it, replace
/// it, or go and get one.
///
/// Present or absent is all this screen can ever say. The key lives in the
/// Keychain and the app cannot read it back for display, which is why there is
/// no reveal affordance and no masked stand-in for a real value.
struct APIKeyView: View {
    @Binding var hasKey: Bool

    @State private var draft = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @FocusState private var fieldFocused: Bool

    private static let consoleURL = URL(string: "https://console.anthropic.com/settings/keys")!

    var body: some View {
        SettingsScreen {
            SettingsCard {
                SettingsRow(title: hasKey ? "Key set" : "No key") {
                    HStack(spacing: Spacing.s3) {
                        Circle()
                            .fill(hasKey ? AppColors.success.default : AppColors.textDisabled)
                            .frame(width: 7, height: 7)
                        if hasKey {
                            Button("Remove") { Task { await remove() } }
                                .buttonStyle(.appDestructiveSmall)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.s3) {
                AppSecureField(
                    label: hasKey ? "Replace key" : "Anthropic API key",
                    placeholder: "sk-ant-…",
                    text: $draft
                )
                .focused($fieldFocused)

                if let errorMessage {
                    Text(errorMessage)
                        .appTextStyle(.small)
                        .foregroundStyle(AppColors.destructive.light)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let savedMessage {
                    Text(savedMessage)
                        .appTextStyle(.small)
                        .foregroundStyle(AppColors.success.default)
                } else if hasKey {
                    SettingsHelp("For security, a saved key is never shown again — paste a new one to replace it.")
                }

                Link(destination: Self.consoleURL) {
                    HStack(spacing: 5) {
                        Text("Get a key from Anthropic")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .appTextStyle(.smallMedium)
                    .foregroundStyle(AppColors.accentGraphic)
                    .tapTargetPadding()
                }
                .padding(.horizontal, Spacing.s1)

                // Commit pairs sit at the trailing edge everywhere in Settings,
                // Cancel first, so the primary is always the rightmost thing.
                HStack(spacing: Spacing.s3) {
                    Spacer(minLength: 0)
                    Button("Cancel", action: cancel)
                        .buttonStyle(.appSecondarySmall)
                        .disabled(isSaving || draft.isEmpty)
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .buttonStyle(.appPrimarySmall)
                        .disabled(isSaving || draft.isEmpty)
                }
            }
        }
        .navigationTitle("Anthropic API key")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cancel() {
        draft = ""
        errorMessage = nil
        fieldFocused = false
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        savedMessage = nil
        defer { isSaving = false }
        do {
            try await AnthropicKeyStore.save(draft)
            draft = ""
            hasKey = true
            fieldFocused = false
            savedMessage = "Saved to this device"
        } catch {
            if error.isCancellation { return }
            // Inline rather than an alert: this is nearly always a bad paste,
            // and the field that needs fixing is right there.
            errorMessage = error.localizedDescription
        }
    }

    private func remove() async {
        errorMessage = nil
        savedMessage = nil
        do {
            try await AnthropicKeyStore.clear()
            hasKey = false
            savedMessage = "Removed from this device"
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
