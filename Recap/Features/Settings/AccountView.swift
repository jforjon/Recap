import SwiftUI

/// Two rows and one action.
///
/// Benchmarked against Apple ID, Linear, Stripe and 1Password, which all do the
/// same three things: one row per errand, each edit in its own focused sheet,
/// and anything dangerous fenced off at the bottom. The screen this replaces was
/// a single form holding email and both password fields, so changing either one
/// meant saving both.
///
/// Sheets rather than pushes keep the flow two levels deep and give Cancel an
/// obvious meaning.
struct AccountView: View {
    let authManager: AuthManager
    @Binding var email: String

    private enum Editing: Identifiable {
        case email, password
        var id: Self { self }
    }

    @State private var editing: Editing?
    @State private var notice: String?
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        SettingsScreen {
            SettingsCard {
                Button { editing = .email } label: {
                    SettingsRow(title: "Email", value: email.isEmpty ? "—" : email, showsChevron: true)
                }
                .buttonStyle(.plain)

                SettingsDivider()

                Button { editing = .password } label: {
                    SettingsRow(title: "Password", showsChevron: true)
                }
                .buttonStyle(.plain)
            }

            if let notice {
                Text(notice)
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.success.default)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.s1)
            }

            if let deleteError {
                Text(deleteError)
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.destructive.light)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.s1)
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Stacked, not side by side: the two are a tap apart and only one of
            // them is reversible.
            VStack(spacing: Spacing.s3) {
                Button("Sign out") {
                    Task { try? await authManager.signOut() }
                }
                .buttonStyle(.appSecondary)
                .disabled(isDeleting)

                Button(isDeleting ? "Deleting…" : "Delete account") {
                    confirmingDelete = true
                }
                .buttonStyle(.appDestructive)
                .disabled(isDeleting)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s4)
            .background(AppColors.background)
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete your account?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your recordings, transcripts, projects and notes are deleted. This can't be undone.")
        }
        .sheet(item: $editing) { which in
            switch which {
            case .email:
                ChangeEmailSheet(authManager: authManager, current: email) { newAddress in
                    // Supabase only applies the address once the user follows the
                    // link, so the row keeps showing the old one until then.
                    notice = "Check \(newAddress) to confirm your new address."
                }
            case .password:
                ChangePasswordSheet(authManager: authManager) {
                    notice = "Password updated."
                }
            }
        }
    }

    /// Server first, then the device.
    ///
    /// The order matters: if the delete fails the user still has an account and
    /// an app that works, whereas wiping locally first would leave them signed in
    /// to data they can no longer see. Local teardown is best-effort — none of it
    /// can fail in a way worth reporting once the account is already gone.
    private func deleteAccount() async {
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }

        do {
            try await StorageService.deleteAccount()
        } catch {
            if error.isCancellation { return }
            deleteError = error.localizedDescription
            return
        }

        // Nothing here lives on the server, so none of it goes with the account.
        try? await AnthropicKeyStore.clear()
        PendingNoteStore.shared.removeAll()
        AudioStore.deleteAll()

        // Signing out is what swaps ContentView back to SignInView; without it
        // the app sits on a Library it can no longer load.
        try? await authManager.signOut()
    }
}

// MARK: - Sheets

/// One field, one line, two pills at the trailing edge with Cancel first.
private struct ChangeEmailSheet: View {
    let authManager: AuthManager
    let current: String
    let onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(title: "Change email") {
            AppTextField(
                label: "New email",
                placeholder: "you@example.com",
                text: $draft,
                contentType: .emailAddress,
                keyboardType: .emailAddress
            )
            helper
        } actions: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.appSecondarySmall)
                .disabled(isSaving)
            Button(isSaving ? "Sending…" : "Send link") { Task { await save() } }
                .buttonStyle(.appPrimarySmall)
                .disabled(isSaving || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { draft = current }
    }

    @ViewBuilder
    private var helper: some View {
        if let errorMessage {
            Text(errorMessage)
                .appTextStyle(.small)
                .foregroundStyle(AppColors.destructive.light)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            SettingsHelp("You'll get a link to confirm. Until you tap it, nothing changes.")
        }
    }

    private func save() async {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard trimmed != current else { dismiss(); return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await authManager.updateEmail(trimmed)
            onSent(trimmed)
            dismiss()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct ChangePasswordSheet: View {
    let authManager: AuthManager
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(title: "Change password") {
            AppSecureField(label: "New password", placeholder: "At least 6 characters",
                           text: $password, contentType: .newPassword)
            AppSecureField(label: "Confirm password", placeholder: "Re-enter it",
                           text: $confirmation, contentType: .newPassword)
            if let errorMessage {
                Text(errorMessage)
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.destructive.light)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.appSecondarySmall)
                .disabled(isSaving)
            Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                .buttonStyle(.appPrimarySmall)
                .disabled(isSaving || password.isEmpty)
        }
    }

    private func save() async {
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }
        guard password == confirmation else {
            errorMessage = "Passwords don't match."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await authManager.updatePassword(password)
            onSaved()
            dismiss()
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}

/// The shared shape of a Settings edit sheet: title, fields, and a trailing
/// action pair. Defined once so the two sheets can't drift apart.
private struct SheetScaffold<Fields: View, Actions: View>: View {
    let title: String
    @ViewBuilder let fields: Fields
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(title)
                .appTextStyle(.heading)
                .foregroundStyle(AppColors.textPrimary)

            fields

            HStack(spacing: Spacing.s3) {
                Spacer(minLength: 0)
                actions
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.background)
        .presentationDetents([.medium])
        .presentationBackground(AppColors.background)
        .presentationCornerRadius(Radius.sheet)
    }
}
