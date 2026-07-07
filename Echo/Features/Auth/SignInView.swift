import SwiftUI

/// Wireframe only — logic is wired up, visual polish (fonts, exact colors) comes later.
struct SignInView: View {
    let authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Echo")
                .font(.largeTitle)

            AppTextField(
                title: "Email",
                text: $email,
                contentType: .emailAddress,
                keyboardType: .emailAddress
            )

            AppSecureField(
                title: "Password",
                text: $password,
                contentType: .password
            )

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Button("Login") {
                submit(signUp: false)
            }
            .buttonStyle(.appPrimary)
            .disabled(isSubmitting || email.isEmpty || password.isEmpty)

            Button("Create an account") {
                submit(signUp: true)
            }
            .buttonStyle(.appSecondary)
            .disabled(isSubmitting || email.isEmpty || password.isEmpty)
        }
        .padding()
    }

    private func submit(signUp: Bool) {
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                if signUp {
                    try await authManager.signUp(email: email, password: password)
                } else {
                    try await authManager.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
