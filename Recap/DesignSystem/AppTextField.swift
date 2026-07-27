import SwiftUI

/// Single-line text input on a charcoal surface.
struct AppTextField: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(title, text: $text)
            .textContentType(contentType)
            .keyboardType(keyboardType)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .appTextStyle(.body)
            .foregroundStyle(AppColors.textPrimary)
            .tint(AppColors.accent)
            .padding(.horizontal, Spacing.s4)
            .frame(minHeight: 48)
            .background(AppColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
    }
}

/// Multi-line text area on a charcoal surface — grows with content.
struct AppTextArea: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 96

    var body: some View {
        TextField(title, text: $text, axis: .vertical)
            .lineLimit(3...10)
            .appTextStyle(.body)
            .foregroundStyle(AppColors.textPrimary)
            .tint(AppColors.accent)
            .padding(Spacing.s4)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(AppColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
    }
}

/// Secure input (passwords / API keys) — same treatment as `AppTextField`.
struct AppSecureField: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType? = nil

    var body: some View {
        SecureField(title, text: $text)
            .textContentType(contentType)
            .appTextStyle(.body)
            .foregroundStyle(AppColors.textPrimary)
            .tint(AppColors.accent)
            .padding(.horizontal, Spacing.s4)
            .frame(minHeight: 48)
            .background(AppColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
    }
}
