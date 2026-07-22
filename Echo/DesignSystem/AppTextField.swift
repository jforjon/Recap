import SwiftUI

/// Standard single-line text input — mirrors .field__input in the web app.
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
            .padding(.horizontal, Spacing.md + 2)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(AppColor.border, lineWidth: 1)
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
            .padding(.horizontal, Spacing.md + 2)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(AppColor.border, lineWidth: 1)
            )
    }
}
