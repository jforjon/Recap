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
                HStack(spacing: Spacing.s3) {
                    Button {
                        recordingManager.discardRecording()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.appIcon)

                    RecordingWaveformView()

                    Text(formattedElapsed)
                        .appTextStyle(.mono)
                        .foregroundStyle(AppColors.neutral600)
                        .frame(minWidth: 36, alignment: .trailing)

                    Button {
                        recordingManager.stopRecording()
                    } label: {
                        Image(systemName: "arrow.up")
                            .fontWeight(.semibold)
                    }
                    .frame(width: 36, height: 36)
                    .background(AppColors.neutral900)
                    .foregroundStyle(AppColors.neutral0)
                    .clipShape(Circle())
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s4)
                .background(
                    Color.clear.background(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
        .padding(.horizontal, Spacing.s4)
        .alert("API keys required", isPresented: $showKeysAlert) {
            Button("Cancel", role: .cancel) {}
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
