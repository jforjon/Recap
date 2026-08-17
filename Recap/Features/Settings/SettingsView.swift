import SwiftUI

struct SettingsView: View {
    let authManager: AuthManager

    /// Which section, if any, is currently in edit mode. Only one at a time so
    /// the page always reads as "view" with a single focused editor.
    private enum EditingSection {
        case account, languages, apiKey
    }

    @State private var editing: EditingSection?

    // Account
    @State private var email = ""
    @State private var emailDraft = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSavingAccount = false
    @State private var accountError: String?
    @State private var accountSavedMessage: String?

    // Anthropic API key. Only ever tracked as present/absent — the secret itself
    // stays in the Keychain and is never pulled into view state.
    @State private var hasAnthropicKey = false
    @State private var keyDraft = ""
    @State private var isSavingKey = false
    @State private var keyError: String?
    @State private var keySavedMessage: String?

    // Spoken languages
    @State private var supportedLanguages: [Locale] = []
    @State private var selectedLanguages: [String] = []
    @State private var defaultLanguage = ""

    // Audio storage
    @State private var audioLocation: AudioStorageLocation = .off
    @State private var audioUsage = ""
    @State private var isMigratingAudio = false

    @State private var errorMessage: String?

    var body: some View {
        Form {
            accountSection
            spokenLanguagesSection
            audioSection
            apiKeySection

            // Trailing action, not a settings row — sits on the page background
            // with no section fill behind it.
            Section {
                Button("Sign out", role: .destructive) {
                    Task { try? await authManager.signOut() }
                }
                .buttonStyle(.appSecondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: Spacing.s4, leading: Spacing.s4,
                                          bottom: 0, trailing: Spacing.s4))
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

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if editing == .account {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    fieldLabel("EMAIL")
                    AppTextField(title: "you@example.com", text: $emailDraft,
                                 contentType: .emailAddress, keyboardType: .emailAddress)

                    fieldLabel("NEW PASSWORD")
                    AppSecureField(title: "Leave blank to keep current",
                                   text: $newPassword, contentType: .newPassword)
                    AppSecureField(title: "Confirm new password",
                                   text: $confirmPassword, contentType: .newPassword)

                    if let accountError {
                        Text(accountError)
                            .appTextStyle(.small)
                            .foregroundStyle(AppColors.destructiveText)
                    }

                    editorButtons(
                        isSaving: isSavingAccount,
                        save: { Task { await saveAccount() } },
                        cancel: cancelAccountEdit
                    )
                }
                .padding(.vertical, Spacing.s1)
            } else {
                readOnlyRow(label: "Email", value: email.isEmpty ? "—" : email)
                readOnlyRow(label: "Password", value: "••••••••")
                savedNote(accountSavedMessage)
            }
        } header: {
            sectionHeader("Account", section: .account) { beginAccountEdit() }
        }
    }

    private func beginAccountEdit() {
        emailDraft = email
        newPassword = ""
        confirmPassword = ""
        accountError = nil
        accountSavedMessage = nil
        editing = .account
    }

    private func cancelAccountEdit() {
        editing = nil
        emailDraft = ""
        newPassword = ""
        confirmPassword = ""
        accountError = nil
    }

    private func saveAccount() async {
        accountError = nil

        let trimmedEmail = emailDraft.trimmingCharacters(in: .whitespaces)
        let emailChanged = !trimmedEmail.isEmpty && trimmedEmail != email
        let wantsPasswordChange = !newPassword.isEmpty || !confirmPassword.isEmpty

        guard !trimmedEmail.isEmpty else {
            accountError = "Email can't be empty."
            return
        }
        if wantsPasswordChange {
            guard newPassword.count >= 6 else {
                accountError = "Password must be at least 6 characters."
                return
            }
            guard newPassword == confirmPassword else {
                accountError = "Passwords don't match."
                return
            }
        }
        guard emailChanged || wantsPasswordChange else {
            cancelAccountEdit()
            return
        }

        isSavingAccount = true
        defer { isSavingAccount = false }
        do {
            if wantsPasswordChange {
                try await authManager.updatePassword(newPassword)
            }
            if emailChanged {
                try await authManager.updateEmail(trimmedEmail)
            }

            var notes: [String] = []
            if wantsPasswordChange { notes.append("Password updated") }
            // Supabase only applies the new address after the user clicks the
            // confirmation link, so don't overwrite the displayed email yet.
            if emailChanged { notes.append("Check \(trimmedEmail) to confirm your new address") }
            accountSavedMessage = notes.joined(separator: " · ")

            editing = nil
            newPassword = ""
            confirmPassword = ""
        } catch {
            if error.isCancellation { return }
            accountError = error.localizedDescription
        }
    }

    // MARK: - Spoken languages

    @ViewBuilder
    private var spokenLanguagesSection: some View {
        // Only render when the device actually supports on-device transcription and
        // reports installable languages — otherwise there's nothing to list.
        if !supportedLanguages.isEmpty {
            Section {
                if editing == .languages {
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

                    Button("Done") { editing = nil }
                        .buttonStyle(.appSecondarySmall)
                } else if selectedLanguages.isEmpty {
                    Text("Using your device language")
                        .appTextStyle(.body)
                        .foregroundStyle(AppColors.neutral500)
                } else {
                    ForEach(selectedLanguages, id: \.self) { code in
                        HStack {
                            Text(displayName(code))
                                .appTextStyle(.body)
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if code == defaultLanguage {
                                Text("DEFAULT")
                                    .appTextStyle(.label)
                                    .foregroundStyle(AppColors.accentGraphic)
                            }
                        }
                    }
                }
            } header: {
                sectionHeader("Spoken languages", section: .languages) { editing = .languages }
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

    // MARK: - Audio

    @ViewBuilder
    private var audioSection: some View {
        Section {
            ForEach(AudioStorageLocation.allCases) { option in
                Button {
                    Task { await changeAudioLocation(to: option) }
                } label: {
                    HStack(alignment: .top, spacing: Spacing.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .appTextStyle(.body)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(option.detail)
                                .appTextStyle(.small)
                                .foregroundStyle(AppColors.neutral600)
                                .fixedSize(horizontal: false, vertical: true)
                            // Choosing iCloud when it isn't set up would silently
                            // behave like "on this iPhone", so say so up front.
                            if option == .cloud && !AudioStore.isCloudAvailable {
                                Text("iCloud Drive is off or you're not signed in — recordings will stay on this iPhone.")
                                    .appTextStyle(.small)
                                    .foregroundStyle(AppColors.warning500)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        if audioLocation == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.accentGraphic)
                        }
                    }
                    .padding(.vertical, Spacing.s1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isMigratingAudio)
            }

            if isMigratingAudio {
                HStack(spacing: Spacing.s2) {
                    ProgressView()
                    Text("Moving recordings…")
                        .appTextStyle(.small)
                        .foregroundStyle(AppColors.neutral600)
                }
            } else if audioLocation != .off {
                readOnlyRow(label: "Audio stored", value: audioUsage)
            }
        } header: {
            Text("Save audio")
        } footer: {
            Text("With this off, only the transcript is kept and nothing is ever written to disk — the way recap has always worked. Turning it on lets you play a recording back with the transcript following along. Roughly 15 MB per hour.")
                .appTextStyle(.small)
                .foregroundStyle(AppColors.neutral600)
        }
    }

    private func changeAudioLocation(to option: AudioStorageLocation) async {
        guard option != audioLocation else { return }
        let previous = audioLocation
        audioLocation = option
        AudioStore.location = option

        // Switching between phone and iCloud moves what's already saved. Turning
        // saving off leaves existing recordings alone — the user asked to stop
        // keeping new audio, not to throw away what they have.
        let movingBetweenStores = option != .off && previous != .off
        let turningOn = option != .off && previous == .off
        if movingBetweenStores || turningOn {
            isMigratingAudio = true
            await AudioStore.migrateAll(to: option)
            isMigratingAudio = false
        }
        audioUsage = AudioStore.formattedTotal()
    }

    // MARK: - Anthropic API key

    @ViewBuilder
    private var apiKeySection: some View {
        Section {
            if editing == .apiKey {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    AppSecureField(title: "sk-ant-…", text: $keyDraft)

                    if let keyError {
                        Text(keyError)
                            .appTextStyle(.small)
                            .foregroundStyle(AppColors.destructiveText)
                    }

                    editorButtons(
                        isSaving: isSavingKey,
                        save: { Task { await saveKey() } },
                        cancel: cancelKeyEdit
                    )
                }
                .padding(.vertical, Spacing.s1)
            } else {
                // Present/absent only. There is no "reveal" affordance and no
                // masked stand-in for a real value: the app cannot read the key
                // back out for display, by design.
                Text(hasAnthropicKey ? "Set" : "Not set")
                    .appTextStyle(.body)
                    .foregroundStyle(hasAnthropicKey ? AppColors.textPrimary : AppColors.neutral500)
                savedNote(keySavedMessage)

                if hasAnthropicKey {
                    Button("Remove key", role: .destructive) {
                        Task { await removeKey() }
                    }
                    .buttonStyle(.appSecondarySmall)
                }
            }
        } header: {
            sectionHeader("Anthropic API key",
                          section: .apiKey,
                          editTitle: hasAnthropicKey ? "Replace" : "Add") { beginKeyEdit() }
        } footer: {
            Text("Stored only on this device — never uploaded to recap's servers, and not included in backups or iCloud. Summaries run on your own Anthropic account instead of recap credits.")
                .appTextStyle(.small)
                .foregroundStyle(AppColors.neutral600)
        }
    }

    private func beginKeyEdit() {
        // Never prefill with the stored key — replacing means pasting a fresh one.
        keyDraft = ""
        keyError = nil
        keySavedMessage = nil
        editing = .apiKey
    }

    private func cancelKeyEdit() {
        editing = nil
        keyDraft = ""
        keyError = nil
    }

    private func saveKey() async {
        isSavingKey = true
        keyError = nil
        keySavedMessage = nil
        defer { isSavingKey = false }
        do {
            try await AnthropicKeyStore.save(keyDraft)
            keyDraft = ""
            hasAnthropicKey = true
            editing = nil
            keySavedMessage = "Saved to this device"
        } catch {
            if error.isCancellation { return }
            // Inline rather than the page alert: this is nearly always a bad
            // paste, and the field the user needs to fix is right there.
            keyError = error.localizedDescription
        }
    }

    private func removeKey() async {
        keySavedMessage = nil
        do {
            try await AnthropicKeyStore.clear()
            hasAnthropicKey = false
            keySavedMessage = "Removed from this device"
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Shared pieces

    /// Section title with a trailing Edit affordance. The button hides while any
    /// section is being edited so only one editor is reachable at a time.
    @ViewBuilder
    private func sectionHeader(
        _ title: String,
        section: EditingSection,
        editTitle: String = "Edit",
        onEdit: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            if editing == nil {
                Button(editTitle, action: onEdit)
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.accentGraphic)
                    .textCase(nil)
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func editorButtons(
        isSaving: Bool,
        save: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Spacing.s3) {
            Button(isSaving ? "Saving…" : "Save", action: save)
                .buttonStyle(.appPrimarySmall)
                .disabled(isSaving)

            Button("Cancel", action: cancel)
                .buttonStyle(.appSecondarySmall)
                .disabled(isSaving)
        }
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .appTextStyle(.label)
            .foregroundStyle(AppColors.neutral600)
    }

    @ViewBuilder
    private func readOnlyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .appTextStyle(.body)
                .foregroundStyle(AppColors.neutral600)
            Spacer()
            Text(value)
                .appTextStyle(.body)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func savedNote(_ message: String?) -> some View {
        if let message {
            Text(message)
                .appTextStyle(.small)
                .foregroundStyle(AppColors.success500)
        }
    }

    // MARK: - Loading

    private func load() async {
        if case let .signedIn(_, userEmail) = authManager.state {
            email = userEmail ?? ""
        }

        supportedLanguages = (await LiveTranscriber.supportedLanguages())
            .sorted { displayName($0.identifier(.bcp47)) < displayName($1.identifier(.bcp47)) }
        #if targetEnvironment(simulator)
        // The Simulator ships no on-device speech models, so `supportedLocales`
        // is empty and this section would be hidden. Show a sample list so the
        // language UI is visible/testable in the Simulator (recording itself
        // still needs a real device).
        if supportedLanguages.isEmpty {
            supportedLanguages = ["en-US", "fr-FR", "es-ES", "de-DE", "it-IT", "pt-BR", "ja-JP"]
                .map { Locale(identifier: $0) }
                .sorted { displayName($0.identifier(.bcp47)) < displayName($1.identifier(.bcp47)) }
        }
        #endif
        selectedLanguages = SpokenLanguageStore.selected
        defaultLanguage = SpokenLanguageStore.defaultLanguage ?? ""

        audioLocation = AudioStore.location
        audioUsage = AudioStore.formattedTotal()

        // Presence check only — no network call, and the secret never leaves
        // the Keychain.
        hasAnthropicKey = (try? await AnthropicKeyStore.isSet()) ?? false
    }
}
