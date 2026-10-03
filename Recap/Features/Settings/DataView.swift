import SwiftUI

/// Where the user's recordings live, and the one action that removes them all.
///
/// This replaced the Account screen. With no accounts there is no email,
/// password or sign-out — the user's iCloud account is the only identity — so
/// what's left is saying where the data is and offering a clean way to wipe it.
struct DataView: View {
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var notice: String?
    @State private var errorMessage: String?
    @State private var showLegacyImport = false
    @State private var legacyImportAvailable = SupabaseImport.isAvailable

    var body: some View {
        SettingsScreen {
            SettingsHelp("Recordings, transcripts, projects and notes are stored on this iPhone and synced to your other devices through your private iCloud database. recap has no server and can't see any of it.")

            // One-off, for the Supabase-era recordings. Gone once they're
            // across; delete with `SupabaseImport`.
            if legacyImportAvailable {
                SettingsCard {
                    Button { showLegacyImport = true } label: {
                        SettingsRow(title: "Import from the earlier version", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                }
            }

            if let notice {
                Text(notice)
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.success.default)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.s1)
            }

            if let errorMessage {
                Text(errorMessage)
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.destructive.light)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.s1)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(isDeleting ? "Deleting…" : "Delete all data") {
                confirmingDelete = true
            }
            .buttonStyle(.appDestructive)
            .disabled(isDeleting)
            // On the button, not the screen, so the popover points at what
            // was tapped instead of floating mid-screen.
            .confirmationDialog(
                "Delete all your data?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    Task { await deleteAll() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes every recording, project and note here and in iCloud, plus saved audio and your API key. This can't be undone.")
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s4)
            .background(AppColors.background)
        }
        .sheet(isPresented: $showLegacyImport, onDismiss: {
            legacyImportAvailable = SupabaseImport.isAvailable
        }) {
            LegacyImportSheet()
        }
        .navigationTitle("Your data")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The store first, then the rest of the device.
    ///
    /// If the store delete fails nothing else has been touched, so the user can
    /// simply try again. What follows is best-effort — none of it can fail in a
    /// way worth reporting once the recordings themselves are gone.
    private func deleteAll() async {
        isDeleting = true
        notice = nil
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await StorageService.deleteAllData()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        try? await AnthropicKeyStore.clear()
        PendingNoteStore.shared.removeAll()
        AudioStore.deleteAll()

        NotificationCenter.default.post(name: StorageService.didDeleteAllData, object: nil)
        notice = "Everything has been deleted."
    }
}
