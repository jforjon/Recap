import SwiftUI
import Supabase

struct NoteDetailView: View {
    let noteId: UUID

    @State private var note: Note?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var speakerContextDraft = ""
    @State private var isSavingSpeakerContext = false

    var body: some View {
        ScrollView {
            if let note {
                VStack(alignment: .leading, spacing: 16) {
                    Text(note.title)
                        .font(.title2.weight(.semibold))

                    HStack {
                        Picker("Category", selection: categoryBinding) {
                            Text("Other").tag(NoteCategory?.none)
                            Text("Talk").tag(NoteCategory?.some(.talk))
                            Text("Training").tag(NoteCategory?.some(.training))
                            Text("Panel").tag(NoteCategory?.some(.panel))
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Text(formatShortDate(note.createdAt))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SPEAKER & CONTEXT")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        AppTextField(title: "Speaker, role, event context…", text: $speakerContextDraft)
                        Button(isSavingSpeakerContext ? "Saving…" : "Save") {
                            Task { await saveSpeakerContext() }
                        }
                        .buttonStyle(.appSecondary)
                        .disabled(isSavingSpeakerContext)
                    }

                    Divider()

                    Text(note.summary)
                        .font(.body)
                }
                .padding()
            } else if isLoading {
                ProgressView()
                    .padding()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var categoryBinding: Binding<NoteCategory?> {
        Binding(
            get: { note?.category },
            set: { newValue in
                Task { await updateCategory(newValue) }
            }
        )
    }

    private func load() async {
        isLoading = true
        do {
            let loaded = try await StorageService.getNoteById(noteId)
            note = loaded
            speakerContextDraft = loaded.speakerContext ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func updateCategory(_ category: NoteCategory?) async {
        do {
            let fields: JSONObject = ["category": category.map { .string($0.rawValue) } ?? .null]
            note = try await StorageService.updateNote(noteId, fields: fields)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSpeakerContext() async {
        isSavingSpeakerContext = true
        defer { isSavingSpeakerContext = false }
        do {
            let trimmed = speakerContextDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let fields: JSONObject = ["speaker_context": trimmed.isEmpty ? .null : .string(trimmed)]
            note = try await StorageService.updateNote(noteId, fields: fields)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
