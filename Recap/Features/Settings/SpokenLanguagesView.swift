import SwiftUI

/// The shortlist of languages offered next to Record, modelled on iOS's own
/// Keyboards screen: a list you curate, an "Add language…" row at the end of it,
/// and Edit for reordering and removal.
///
/// **The first language is the default.** That is the whole answer to "how do I
/// change it?" — the same gesture as reordering, rather than a separate Picker
/// buried in an edit mode. `SpokenLanguageStore.move` keeps the stored default
/// pinned to the first entry so the Record picker agrees.
///
/// This is the one Settings screen built on `List` rather than `SettingsCard`.
/// Reordering and swipe-to-delete are native list behaviours, and reimplementing
/// them over a custom container would be worse than borrowing the container.
/// Every colour is still the app's own.
struct SpokenLanguagesView: View {
    private var languages: SpokenLanguageStore { SpokenLanguageStore.shared }

    var body: some View {
        List {
            Section {
                ForEach(languages.selected, id: \.self) { code in
                    row(for: code)
                }
                .onMove { languages.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { languages.remove(atOffsets: $0) }

                NavigationLink {
                    AddLanguageView()
                } label: {
                    Text("Add language…")
                        .appTextStyle(.body)
                        .foregroundStyle(AppColors.accentGraphic)
                }
                .listRowBackground(AppColors.surface)
            } footer: {
                SettingsHelp(footerText)
                    .padding(.top, Spacing.s2)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 50)
        .recapBackground()
        .navigationTitle("Spoken languages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !languages.selected.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton().tint(AppColors.accentGraphic)
                }
            }
        }
        .task { await languages.loadAvailable() }
    }

    @ViewBuilder
    private func row(for code: String) -> some View {
        HStack(spacing: Spacing.s3) {
            Text(SpokenLanguageStore.displayName(code))
                .appTextStyle(.body)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if code == languages.selected.first {
                SettingsTag(text: "Default")
            } else if languages.isInstalled(code) == false {
                // Only when the device has actually told us. `isInstalled`
                // returns nil before the model list loads and on the Simulator,
                // and a tag that guesses is worse than no tag.
                SettingsTag(text: "Not downloaded", isChosen: false)
            }
        }
        .listRowBackground(AppColors.surface)
    }

    private var footerText: String {
        languages.selected.isEmpty
            ? "Every language this iPhone can transcribe is offered next to Record. Add some to shorten that list."
            : "The first is the default. Tap Edit to reorder or remove."
    }
}
