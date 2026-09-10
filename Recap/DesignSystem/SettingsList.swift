import SwiftUI

/// The four shapes a Settings screen is built from, defined once.
///
/// The redesign turns on one rule: a reader must be able to tell what a thing
/// does from its shape alone, before reading a word of it.
///
/// * `SettingsCard` + `SettingsRow` — something you tap. Surface fill, hairline
///   separators, full width, a chevron or a tick.
/// * `SettingsTag` — state the row carries. Uppercase, inside the row it
///   belongs to, never on its own.
/// * `SettingsHelp` — information. Quiet text on the page ground with no fill,
///   no border and no rule, so it can't be mistaken for a row.
/// * The `.appPrimary` / `.appSecondary` / `.appDestructive` pills — an action.
///
/// The old screen blurred all four: read-only values sat in tappable-looking
/// rows, actions sat in section headers, and explanations sat in Form footers.

// MARK: - Container

/// A group of rows on one charcoal surface. Rows are separated by
/// `SettingsDivider`, which callers place between them — with only two or three
/// rows to a card, being explicit reads better than inferring it.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(AppColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(AppColors.separator, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.separator)
            .frame(height: 1)
    }
}

/// Uppercase label above a card. `trailing` carries a count where one helps.
struct SettingsGroupLabel: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appTextStyle(.label)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
            Spacer(minLength: Spacing.s3)
            if let trailing {
                Text(trailing)
                    .appTextStyle(.label)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.textFaint)
            }
        }
        .padding(.horizontal, Spacing.s1)
    }
}

/// Information. Never a row, never a card — see the type comment above.
struct SettingsHelp: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .appTextStyle(.small)
            .foregroundStyle(AppColors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s1)
    }
}

/// State a row carries. Accent when the user chose it, muted when the system
/// did — `Default` against `Not downloaded`.
struct SettingsTag: View {
    let text: String
    var isChosen: Bool = true

    var body: some View {
        Text(text)
            .appTextStyle(.label)
            .textCase(.uppercase)
            .foregroundStyle(isChosen ? AppColors.accentGraphic : AppColors.textFaint)
            .layoutPriority(1)
    }
}

// MARK: - Rows

/// A row inside a `SettingsCard`.
///
/// `value` is the row's current setting, shown on the right — the single change
/// that lets the index answer "what is everything set to?" without a tap.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var value: String? = nil
    var titleColor: Color = AppColors.textPrimary
    var showsChevron: Bool = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Text(title)
                .appTextStyle(.body)
                .foregroundStyle(titleColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let value {
                Text(value)
                    .appTextStyle(.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            trailing

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textFaint)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, 13)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(
        title: String,
        value: String? = nil,
        titleColor: Color = AppColors.textPrimary,
        showsChevron: Bool = false
    ) {
        self.init(
            title: title,
            value: value,
            titleColor: titleColor,
            showsChevron: showsChevron
        ) { EmptyView() }
    }
}

/// A row that pushes a screen. The whole row is the target, which is well past
/// the 44pt minimum at 50pt tall.
struct SettingsLinkRow<Destination: View>: View {
    let title: String
    var value: String? = nil
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRow(title: title, value: value, showsChevron: true)
        }
        .buttonStyle(.plain)
    }
}

/// A selectable option with a description under it — the audio locations, and
/// anything else where the choice needs a sentence to be fair.
struct SettingsOptionRow: View {
    let title: String
    let detail: String
    var note: String? = nil
    var noteColor: Color = AppColors.warning.light
    var meta: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .appTextStyle(.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(detail)
                        .appTextStyle(.small)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let meta {
                        Text(meta)
                            .appTextStyle(.small)
                            .foregroundStyle(AppColors.accentGraphic)
                    }
                    if let note {
                        Text(note)
                            .appTextStyle(.small)
                            .foregroundStyle(noteColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accentGraphic)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, 13)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen scaffold

/// The scrolling body every Settings screen shares: charcoal ground, 16pt
/// gutters, 20pt between groups.
struct SettingsScreen<Content: View>: View {
    var topPadding: CGFloat = Spacing.s2
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s5) {
                content
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, topPadding)
            .padding(.bottom, Spacing.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .recapBackground()
    }
}
