import SwiftUI

struct PersonalNotesView: View {
    let projectId: UUID
    let projectName: String

    @State private var notes: [PersonalNote] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showDeleteAllConfirm = false

    @State private var voiceTranscriber = LiveTranscriber()
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
                        MarkdownText(markdown: note.content)
                        HStack {
                            if note.type == .voice {
                                Label("Voice", systemImage: "mic.fill")
                                    .appTextStyle(.mono)
                                    .foregroundStyle(AppColors.neutral500)
                            }
                            Spacer()
                            Text(formatShortDate(note.createdAt))
                                .appTextStyle(.mono)
                                .foregroundStyle(AppColors.neutral500)
                        }
                    }
                    .listRowBackground(AppColors.neutral200)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await delete(note.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(AppColors.destructive)
                    }
                }
            }
            .listStyle(.plain)
            .recapBackground()

            Divider()
                .overlay(AppColors.separator)

            composer
                .padding()
        }
        .background(AppColors.background.ignoresSafeArea())
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
        .alert("Delete all personal notes?", isPresented: $showDeleteAllConfirm) {
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
            if error.isCancellation { return }
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
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ id: UUID) async {
        notes.removeAll { $0.id == id }
        do {
            try await StorageService.deletePersonalNote(id)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
            await load()
        }
    }

    private func deleteAll() async {
        notes = []
        do {
            try await StorageService.deleteAllPersonalNotes(projectId: projectId)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
            await load()
        }
    }

    // MARK: - Voice notes

    private func startVoice() async {
        do {
            // Transcribes on-device; requests mic + speech permission internally.
            try await voiceTranscriber.start()
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
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func discardVoice() {
        voiceTimerTask?.cancel()
        voiceTimerTask = nil
        isRecordingVoice = false
        voiceElapsed = 0
        Task { await voiceTranscriber.cancel() }
    }

    private func stopAndSaveVoice() async {
        voiceTimerTask?.cancel()
        voiceTimerTask = nil
        isRecordingVoice = false
        voiceElapsed = 0
        isTranscribingVoice = true
        defer { isTranscribingVoice = false }

        let transcript = await voiceTranscriber.finish()
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let note = try await StorageService.createPersonalNote(projectId: projectId, content: trimmed, type: .voice)
            notes.append(note)
        } catch {
            if error.isCancellation { return }
            errorMessage = error.localizedDescription
        }
    }
}
