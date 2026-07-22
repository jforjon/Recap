import SwiftUI

struct PersonalNotesView: View {
    let projectId: UUID
    let projectName: String

    @State private var notes: [PersonalNote] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showDeleteAllConfirm = false

    @State private var voiceRecorder = AudioChunkRecorder()
    @State private var isRecordingVoice = false
    @State private var isTranscribingVoice = false
    @State private var voiceElapsed = 0
    @State private var voiceTimerTask: Task<Void, Never>?
    @State private var voiceStartedAt: Date?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.content)
                        HStack {
                            if note.type == .voice {
                                Label("Voice", systemImage: "mic.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatShortDate(note.createdAt))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await delete(note.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)

            Divider()

            composer
                .padding()
        }
        .navigationTitle(projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete all notes", role: .destructive) {
                        showDeleteAllConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
        .confirmationDialog("Delete all personal notes?", isPresented: $showDeleteAllConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteAll() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var composer: some View {
        if isRecordingVoice {
            HStack(spacing: Spacing.md) {
                Button {
                    discardVoice()
                } label: {
                    Image(systemName: "trash")
                }

                Text(formattedVoiceElapsed)
                    .font(.callout.monospaced())
                    .frame(maxWidth: .infinity)

                Button {
                    Task { await stopAndSaveVoice() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(AppColor.cardBackground)
            )
        } else {
            HStack {
                AppTextField(title: isTranscribingVoice ? "Transcribing…" : "Write a note…", text: $draft)
                    .disabled(isTranscribingVoice)

                if draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        Task { await startVoice() }
                    } label: {
                        Image(systemName: "mic")
                    }
                    .disabled(isTranscribingVoice)
                } else {
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(isSending)
                }
            }
        }
    }

    private var formattedVoiceElapsed: String {
        let m = voiceElapsed / 60
        let s = voiceElapsed % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func load() async {
        do {
            notes = try await StorageService.getPersonalNotes(projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let note = try await StorageService.createPersonalNote(projectId: projectId, content: text, type: .text)
            notes.append(note)
            draft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ id: UUID) async {
        notes.removeAll { $0.id == id }
        do {
            try await StorageService.deletePersonalNote(id)
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func deleteAll() async {
        notes = []
        do {
            try await StorageService.deleteAllPersonalNotes(projectId: projectId)
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    // MARK: - Voice notes

    private func startVoice() async {
        guard await voiceRecorder.requestPermission() else {
            errorMessage = "Microphone access is required to record a voice note."
            return
        }
        do {
            try voiceRecorder.configureSession()
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("personal_note_\(UUID().uuidString).m4a")
            try voiceRecorder.startChunk(at: tempURL)
            voiceStartedAt = Date()
            voiceElapsed = 0
            isRecordingVoice = true
            voiceTimerTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    if let start = voiceStartedAt {
                        voiceElapsed = Int(Date().timeIntervalSince(start))
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardVoice() {
        voiceTimerTask?.cancel()
        voiceTimerTask = nil
        voiceRecorder.stopAndDeleteChunk()
        voiceRecorder.deactivateSession()
        isRecordingVoice = false
        voiceElapsed = 0
    }

    private func stopAndSaveVoice() async {
        voiceTimerTask?.cancel()
        voiceTimerTask = nil
        guard let url = voiceRecorder.stopChunk() else {
            isRecordingVoice = false
            return
        }
        voiceRecorder.deactivateSession()
        isRecordingVoice = false
        voiceElapsed = 0
        isTranscribingVoice = true
        defer { isTranscribingVoice = false }

        do {
            let token = try await SupabaseService.client.auth.session.accessToken
            let transcript = try await TranscriptionClient.transcribe(fileURL: url, accessToken: token)
            try? FileManager.default.removeItem(at: url)
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let note = try await StorageService.createPersonalNote(projectId: projectId, content: trimmed, type: .voice)
            notes.append(note)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
