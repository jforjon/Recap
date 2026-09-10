import SwiftUI

/// The searchable picker behind "Add language…".
///
/// One list in relevance order rather than sections split by download state:
/// whether a model is already on the phone is a tag the row carries, not a
/// reason to reorder the results. Nothing here quotes a download size or a
/// reservation cap, because neither number is known — the tag is true without
/// them.
struct AddLanguageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var languages: SpokenLanguageStore { SpokenLanguageStore.shared }

    var body: some View {
        List {
            Section {
                ForEach(matches, id: \.self) { code in
                    Button {
                        languages.add(code)
                        dismiss()
                    } label: {
                        HStack(spacing: Spacing.s3) {
                            Text(SpokenLanguageStore.displayName(code))
                                .appTextStyle(.body)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if languages.isInstalled(code) == false {
                                SettingsTag(text: "Not downloaded", isChosen: false)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppColors.surface)
                }
            } header: {
                if !matches.isEmpty {
                    Text(matches.count == 1 ? "1 language" : "\(matches.count) languages")
                        .appTextStyle(.label)
                        .foregroundStyle(AppColors.textTertiary)
                }
            } footer: {
                if !matches.isEmpty {
                    SettingsHelp("iOS limits how many languages can be kept on this iPhone. Remove one to add another.")
                        .padding(.top, Spacing.s2)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 50)
        .recapBackground()
        .overlay {
            if matches.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: query.isEmpty ? "Nothing left to add" : "No match",
                    message: query.isEmpty
                        ? "Every language this iPhone can transcribe is already on your list."
                        : "Try the language's own name — Deutsch as well as German."
                )
            }
        }
        .searchable(text: $query, prompt: "Search languages")
        .navigationTitle("Add language")
        .navigationBarTitleDisplayMode(.inline)
        .task { await languages.loadAvailable() }
    }

    /// Everything the device supports that isn't shortlisted yet, narrowed by the
    /// search. Matching is diacritic- and case-insensitive so "francais" finds
    /// Français.
    private var matches: [String] {
        let remaining = languages.available.filter { !languages.selected.contains($0) }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return remaining }
        return remaining.filter {
            SpokenLanguageStore.displayName($0)
                .range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
