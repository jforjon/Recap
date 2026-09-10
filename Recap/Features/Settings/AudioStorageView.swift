import SwiftUI

/// Where saved audio lives, and the one action that can undo it.
///
/// The storage figures hang off the option they belong to rather than sitting in
/// a read-only row underneath — the count is a consequence of the choice, not a
/// setting of its own, and as a row it looked like something you could change.
struct AudioStorageView: View {
    @State private var isMigrating = false
    @State private var usage = ""
    @State private var count = 0
    @State private var confirmingDelete = false

    private var audio: AudioSettings { AudioSettings.shared }

    var body: some View {
        SettingsScreen {
            SettingsHelp("Off keeps only the transcript. On lets you play a recording back with the transcript following along — about 15 MB an hour.")

            SettingsCard {
                ForEach(Array(AudioStorageLocation.allCases.enumerated()), id: \.element) { index, option in
                    if index > 0 { SettingsDivider() }
                    SettingsOptionRow(
                        title: option.title,
                        detail: option.detail,
                        note: note(for: option),
                        meta: meta(for: option),
                        isSelected: audio.location == option
                    ) {
                        Task { await change(to: option) }
                    }
                    .disabled(isMigrating)
                }
            }

            if isMigrating {
                HStack(spacing: Spacing.s2) {
                    ProgressView()
                    Text("Moving recordings…")
                        .appTextStyle(.small)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.horizontal, Spacing.s1)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if count > 0 {
                Button("Delete all audio") { confirmingDelete = true }
                    .buttonStyle(.appDestructive)
                    .disabled(isMigrating)
                    .padding(.horizontal, Spacing.s4)
                    .padding(.bottom, Spacing.s4)
                    .background(AppColors.background)
            }
        }
        .navigationTitle("Save audio")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete all saved audio?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(usage)", role: .destructive) {
                AudioStore.deleteAll()
                refresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Transcripts, notes and summaries are kept.")
        }
        .task { refresh() }
    }

    /// The saved figures, shown only against the location currently in use —
    /// against the other two they'd describe something that isn't happening.
    private func meta(for option: AudioStorageLocation) -> String? {
        guard option == audio.location, option != .off, count > 0 else { return nil }
        return count == 1 ? "1 recording · \(usage)" : "\(count) recordings · \(usage)"
    }

    /// Choosing iCloud when it isn't set up behaves exactly like "on this
    /// iPhone", so say so before the tap rather than after it.
    private func note(for option: AudioStorageLocation) -> String? {
        guard option == .cloud, !AudioStore.isCloudAvailable else { return nil }
        return "iCloud Drive is off or you're not signed in — recordings would stay on this iPhone."
    }

    private func change(to option: AudioStorageLocation) async {
        let previous = audio.location
        guard option != previous else { return }
        audio.setLocation(option)

        // Turning saving on, or moving between phone and iCloud, brings what's
        // already saved along. Turning it off leaves existing recordings alone —
        // the user asked to stop keeping new audio, not to discard what they have.
        if option != .off {
            isMigrating = true
            await AudioStore.migrateAll(to: option)
            isMigrating = false
        }
        refresh()
    }

    private func refresh() {
        usage = AudioStore.formattedTotal()
        count = AudioStore.savedCount()
    }
}
