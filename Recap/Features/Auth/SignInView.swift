import SwiftUI

struct SignInView: View {
    let authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: Spacing.s7) {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    logoMark
                    Text("recap")
                        .font(AppFont.sans(40, medium: true))
                        .tracking(-1.2)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Talks, panels and trainings — transcribed live, on your device.")
                        .appTextStyle(.body)
                        .foregroundStyle(AppColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.s3) {
                    fieldLabel("EMAIL")
                    AppTextField(
                        title: "you@studio.co",
                        text: $email,
                        contentType: .emailAddress,
                        keyboardType: .emailAddress
                    )
                    fieldLabel("PASSWORD")
                    AppSecureField(
                        title: "Password",
                        text: $password,
                        contentType: .password
                    )

                    if let errorMessage {
                        HStack(spacing: Spacing.s2) {
                            Image(systemName: "exclamationmark.circle")
                            Text(errorMessage)
                        }
                        .appTextStyle(.small)
                        .foregroundStyle(AppColors.destructiveText)
                    }
                }

                VStack(spacing: Spacing.s3) {
                    Button("Sign in") {
                        submit(signUp: false)
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty)

                    Button("Create account") {
                        submit(signUp: true)
                    }
                    .buttonStyle(.appSecondary)
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty)

                    Text("Transcription runs on device. Audio never leaves your iPhone.")
                        .appTextStyle(.mono)
                        .foregroundStyle(AppColors.textFaint)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.s1)
                }
            }
            .padding(Spacing.s6)
            .frame(maxWidth: 440)
        }
    }

    /// The recap mark — three decaying amber bars, matching the app icon.
    private var logoMark: some View {
        VStack(spacing: 5) {
            Capsule().fill(AppColors.accentGraphic).frame(width: 46, height: 7)
            Capsule().fill(AppColors.accentGraphic.opacity(0.58)).frame(width: 32, height: 7)
            Capsule().fill(AppColors.accentGraphic.opacity(0.30)).frame(width: 18, height: 7)
        }
        .frame(width: 46, alignment: .leading)
        .padding(.bottom, Spacing.s1)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .appTextStyle(.mono)
            .foregroundStyle(AppColors.textTertiary)
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
                if error.isCancellation { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
