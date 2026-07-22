import SwiftUI

struct RecordingBarView: View {
    let recordingManager: RecordingManager

    @State private var isStarting = false
    @State private var showKeysAlert = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            switch recordingManager.phase {
            case .idle:
                Button(isStarting ? "Starting…" : "Start recording") {
                    Task { await start() }
                }
                .buttonStyle(.appPrimary)
                .disabled(isStarting)

            case .recording:
                HStack(spacing: 12) {
                    Button {
                        recordingManager.discardRecording()
                    } label: {
                        Image(systemName: "trash")
                    }

                    Text(formattedElapsed)
                        .font(.callout.monospaced())
                        .frame(maxWidth: .infinity)

                    Button {
                        recordingManager.stopRecording()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
        }
        .padding(.horizontal)
        .alert("API keys required", isPresented: $showKeysAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add your OpenAI and Anthropic API keys in Settings to start recording.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var formattedElapsed: String {
        let m = recordingManager.elapsed / 60
        let s = recordingManager.elapsed % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        let hasKeys = await recordingManager.checkHasKeys()
        guard hasKeys else {
            showKeysAlert = true
            return
        }
        do {
            try await recordingManager.startRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
