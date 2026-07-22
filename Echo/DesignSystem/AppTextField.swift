import SwiftUI

/// Standard single-line text input — 1:1 port of .field__input in components.css.
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
            .foregroundStyle(AppColors.neutral800)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(AppColors.neutral0)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(AppColors.neutral300, lineWidth: 0.5)
            )
    }
}

/// Standard secure input (passwords) — same visual treatment as AppTextField.
struct AppSecureField: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType? = nil

    var body: some View {
        SecureField(title, text: $text)
            .textContentType(contentType)
            .appTextStyle(.body)
            .foregroundStyle(AppColors.neutral800)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(AppColors.neutral0)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(AppColors.neutral300, lineWidth: 0.5)
            )
    }
}
