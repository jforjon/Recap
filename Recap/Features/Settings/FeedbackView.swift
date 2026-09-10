import SwiftUI

/// One box and one button.
///
/// No type picker: an idea reads differently from a bug, and asking the reporter
/// to file it first is a form filled in for the developer's convenience. No
/// reply address either — this is feedback, not a contact form, and the screen
/// says so once rather than disclaiming it three times.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSend = false

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        SettingsScreen {
            if didSend {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Sent",
                    message: "Thanks — it goes straight to the person who builds this."
                )
                .padding(.top, Spacing.s8)
            } else {
                AppTextArea(
                    placeholder: "What's on your mind?",
                    text: $message,
                    minHeight: 196
                )

                if let errorMessage {
                    Text(errorMessage)
                        .appTextStyle(.small)
                        .foregroundStyle(AppColors.destructive.light)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.s1)
                }

                HStack {
                    Spacer(minLength: 0)
                    Button(isSending ? "Sending…" : "Send") { Task { await send() } }
                        .buttonStyle(.appPrimarySmall)
                        .disabled(!canSend)
                }
            }
        }
        .navigationTitle("Send feedback")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await FeedbackClient.send(message)
            message = ""
            didSend = true
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
