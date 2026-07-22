import SwiftUI

struct PersonalNotesView: View {
    let projectId: UUID
    let projectName: String

    @State private var notes: [PersonalNote] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .trailing, spacing: 8) {
                        ForEach(notes) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.content)
                                Text(formatShortDate(note.createdAt))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                            .frame(maxWidth: 280, alignment: .trailing)
                            .id(note.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: notes.count) {
                    if let last = notes.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack {
                AppTextField(title: "Write a note…", text: $draft)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            }
            .padding()
        }
        .navigationTitle(projectName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
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
}
