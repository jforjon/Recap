import SwiftUI

/// "We found recordings from the old version" — the one screen of the one-off
/// Supabase import. Offered at launch when the old build left a session behind,
/// and from Settings → Your data otherwise. Delete with `SupabaseImport`.
///
/// With a saved session it is one tap. Without one (the old sign-in expired, or
/// the app is now signed by a different team and can't see it) it asks for the
/// old account's email and password, used for this import only.
struct LegacyImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var needsSignIn = !SupabaseImport.shouldOfferOnLaunch
    @State private var email = ""
    @State private var password = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var result: SupabaseImport.Summary?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(result == nil ? "Bring your recordings across" : "All done")
                .appTextStyle(.heading)
                .foregroundStyle(AppColors.textPrimary)

            if let result {
                Text(result.message + " They're on this iPhone now and sync through iCloud.")
                    .appTextStyle(.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(needsSignIn
                     ? "Sign in to the account you used with the earlier version of recap, and its recordings, projects and notes will be copied here."
                     : "You have recordings, projects and notes from the earlier version of recap. Import them so they're kept on this iPhone and synced through iCloud.")
                    .appTextStyle(.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if needsSignIn {
                    AppTextField(label: "Email", placeholder: "you@example.com",
                                 text: $email, contentType: .username, keyboardType: .emailAddress)
                    AppSecureField(label: "Password", placeholder: "Old account password",
                                   text: $password, contentType: .password)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.destructive.light)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.s3) {
                Spacer(minLength: 0)
                if result != nil {
                    Button("Done") { dismiss() }
                        .buttonStyle(.appPrimarySmall)
                } else {
                    Button("Not now") { dismiss() }
                        .buttonStyle(.appSecondarySmall)
                        .disabled(isImporting)
                    Button(isImporting ? "Importing…" : "Import") { Task { await runImport() } }
                        .buttonStyle(.appPrimarySmall)
                        .disabled(isImporting || (needsSignIn && (email.isEmpty || password.isEmpty)))
                }
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.background)
        .presentationDetents([.medium])
        .presentationBackground(AppColors.background)
        .presentationCornerRadius(Radius.sheet)
        .interactiveDismissDisabled(isImporting)
    }

    private func runImport() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            let summary = needsSignIn
                ? try await SupabaseImport.importSigningIn(
                    email: email.trimmingCharacters(in: .whitespaces), password: password)
                : try await SupabaseImport.importWithSavedSession()
            password = ""
            result = summary
            NotificationCenter.default.post(name: StorageService.didImport, object: nil)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
            // A dead saved session can't be retried; fall through to signing in.
            needsSignIn = true
        }
    }
}
