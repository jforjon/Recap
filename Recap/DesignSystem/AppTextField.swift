import SwiftUI

/// The persistent field label.
///
/// A placeholder disappears on the first keystroke — which is exactly the point
/// at which the user most needs to know what they are filling in, and the point
/// at which two adjacent secure fields become indistinguishable. So the name
/// lives here, above the input, and stays put.
///
/// This replaces the `fieldLabel` helper that had been redeclared in both
/// `SignInView` and `SettingsView` with *different* styling, so even the
/// labelled fields didn't match each other.
private struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .appTextStyle(.label)
            .textCase(.uppercase)
            .foregroundStyle(AppColors.textSecondary)
    }
}

/// Stacks an optional label over an input. The gap is deliberately tight, so a
/// label binds to its own field rather than floating between two of them; the
/// caller supplies the larger spacing *between* fields.
private struct LabelledField<Field: View>: View {
    let label: String?
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            if let label {
                FieldLabel(text: label)
            }
            field
        }
    }
}

/// The charcoal input chrome — surface fill, hairline border, input radius.
/// Defined once so the three field types cannot drift apart.
private struct FieldChrome: ViewModifier {
    var minHeight: CGFloat = 48
    var alignment: Alignment = .center
    var insets = EdgeInsets(top: 0, leading: Spacing.s4, bottom: 0, trailing: Spacing.s4)

    func body(content: Content) -> some View {
        content
            .appTextStyle(.body)
            .foregroundStyle(AppColors.textPrimary)
            .tint(AppColors.accentGraphic)
            .padding(insets)
            .frame(minHeight: minHeight, alignment: alignment)
            .background(AppColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
    }
}

private extension View {
    func fieldChrome(minHeight: CGFloat = 48,
                     alignment: Alignment = .center,
                     insets: EdgeInsets = EdgeInsets(top: 0, leading: Spacing.s4,
                                                     bottom: 0, trailing: Spacing.s4)) -> some View {
        modifier(FieldChrome(minHeight: minHeight, alignment: alignment, insets: insets))
    }
}

/// Single-line text input on a charcoal surface.
///
/// `label` is optional only for inline uses — a composer sitting in an `HStack`
/// beside its own buttons, where a stacked label would break the row. Anywhere
/// the field stands on its own, pass one.
struct AppTextField: View {
    var label: String? = nil
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        LabelledField(label: label) {
            TextField(placeholder, text: $text)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .fieldChrome()
                // The placeholder leaves the accessibility tree once the field
                // has content, so without this a filled field announces only
                // its value.
                .accessibilityLabel(label ?? placeholder)
        }
    }
}

/// Multi-line text area on a charcoal surface — grows with content.
struct AppTextArea: View {
    var label: String? = nil
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 96

    var body: some View {
        LabelledField(label: label) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(3...10)
                .fieldChrome(minHeight: minHeight,
                             alignment: .topLeading,
                             insets: EdgeInsets(top: Spacing.s4, leading: Spacing.s4,
                                                bottom: Spacing.s4, trailing: Spacing.s4))
                .accessibilityLabel(label ?? placeholder)
        }
    }
}

/// Secure input (passwords / API keys) — same treatment as `AppTextField`.
///
/// This is the type that most needs its label: once filled, every secure field
/// renders as the same row of dots.
struct AppSecureField: View {
    var label: String? = nil
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType? = nil

    var body: some View {
        LabelledField(label: label) {
            SecureField(placeholder, text: $text)
                .textContentType(contentType)
                .fieldChrome()
                .accessibilityLabel(label ?? placeholder)
        }
    }
}
