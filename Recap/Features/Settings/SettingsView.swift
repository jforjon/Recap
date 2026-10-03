import SwiftUI

/// Settings, level one.
///
/// Purely navigational: five rows across four named groups, each showing its
/// current value on the right, each pushing a screen that owns its own state.
/// Nothing here is edited in place.
///
/// That is the whole point of the rebuild. The screen this replaced kept a
/// single `editing` enum shared by three sections, so opening one editor
/// silently disabled the other two, and a value could only be read by entering
/// edit mode. With every editable thing behind its own push there is no shared
/// mode left to leak.
struct SettingsView: View {
    @State private var hasAnthropicKey = false

    // Both stores are observable, so a change made two screens down redraws
    // these rows on the way back without any callback plumbing.
    private var languages: SpokenLanguageStore { SpokenLanguageStore.shared }
    private var audio: AudioSettings { AudioSettings.shared }

    var body: some View {
        SettingsScreen(topPadding: 0) {
            Text("Settings")
                .appTextStyle(.displayBold)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.vertical, Spacing.s1)

            captureGroup
            intelligenceGroup
            supportGroup
            dataGroup

            Text(Self.versionString)
                .appTextStyle(.mono)
                .foregroundStyle(AppColors.textFaint)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Spacing.s2)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: StorageService.didDeleteAllData)) { _ in
            hasAnthropicKey = false
        }
    }

    // MARK: - Groups

    private var captureGroup: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            SettingsGroupLabel(title: "Capture")
            SettingsCard {
                SettingsLinkRow(title: "Spoken languages", value: languageSummary) {
                    SpokenLanguagesView()
                }
                SettingsDivider()
                SettingsLinkRow(title: "Save audio", value: audio.location.title) {
                    AudioStorageView()
                }
            }
        }
    }

    private var intelligenceGroup: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            SettingsGroupLabel(title: "Intelligence")
            SettingsCard {
                NavigationLink {
                    APIKeyView(hasKey: $hasAnthropicKey)
                } label: {
                    SettingsRow(title: "Anthropic API key", showsChevron: true) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(hasAnthropicKey ? AppColors.success.default : AppColors.textDisabled)
                                .frame(width: 7, height: 7)
                            Text(hasAnthropicKey ? "Set" : "Not set")
                                .appTextStyle(.body)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            SettingsHelp("Summaries use your own Anthropic account.")
        }
    }

    private var supportGroup: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            SettingsGroupLabel(title: "Support")
            SettingsCard {
                SettingsLinkRow(title: "Send feedback") {
                    FeedbackView()
                }
            }
        }
    }

    private var dataGroup: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            SettingsGroupLabel(title: "Data")
            SettingsCard {
                SettingsLinkRow(title: "Your data") {
                    DataView()
                }
            }
        }
    }

    // MARK: - Values

    /// "English (UK) +2" — the default first, then how many more are shortlisted.
    /// An empty shortlist means every language is on offer next to Record, which
    /// the row says rather than showing a bare dash.
    private var languageSummary: String {
        guard let code = languages.defaultLanguage else { return "Not set" }
        let name = SpokenLanguageStore.displayName(code)
        let extras = languages.selected.count - 1
        guard languages.selected.count > 1 else {
            return languages.selected.isEmpty ? "\(name) · all offered" : name
        }
        return "\(name) +\(extras)"
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "recap \(version) (\(build))"
    }

    private func load() async {
        await languages.loadAvailable()
        hasAnthropicKey = (try? await AnthropicKeyStore.isSet()) ?? false
    }
}
