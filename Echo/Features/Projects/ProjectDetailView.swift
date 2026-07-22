import SwiftUI
import Supabase

struct ProjectDetailView: View {
    let projectId: UUID
    let recordingManager: RecordingManager

    @State private var project: Project?
    @State private var notes: [Note] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isGeneratingSummary = false
    @State private var isStartingRecording = false
    @State private var showKeysAlert = false

    var body: some View {
        List {
            Section("Recordings") {
                if notes.isEmpty && !isLoading {
                    Text("No recordings yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(notes) { note in
                    NavigationLink(value: note) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let category = note.category {
                                AppChip(text: category.displayText, dotColor: category.dotColor)
                            }
                            Text(note.title).font(.body.weight(.medium))
                        }
                    }
                }
            }

            Section("Personal notes") {
                NavigationLink("Open personal notes") {
                    PersonalNotesView(projectId: projectId, projectName: project?.name ?? "")
                }
            }

            Section("Summary") {
                if let summary = project?.notes, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                } else {
                    Text("No summary yet.")
                        .foregroundStyle(.secondary)
                }
                Button(isGeneratingSummary ? "Generating…" : (project?.notes?.isEmpty == false ? "Update summary" : "Generate summary")) {
                    Task { await generateSummary() }
                }
                .buttonStyle(.appSecondary)
                .disabled(isGeneratingSummary || notes.isEmpty)
            }

            Section {
                Button(isStartingRecording ? "Starting…" : "Start recording") {
                    Task { await startRecording() }
                }
                .buttonStyle(.appPrimary)
                .disabled(isStartingRecording || recordingManager.phase == .recording)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(project?.name ?? "Project")
        .navigationDestination(for: Note.self) { note in
            NoteDetailView(noteId: note.id)
        }
        .task { await load() }
        .refreshable { await load() }
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

    private func load() async {
        isLoading = true
        do {
            async let projectResult = StorageService.getProjectById(projectId)
            async let notesResult = StorageService.getNotesByProjectId(projectId)
            project = try await projectResult
            notes = try await notesResult
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func generateSummary() async {
        isGeneratingSummary = true
        defer { isGeneratingSummary = false }
        do {
            let token = try await SupabaseService.client.auth.session.accessToken
            let summary = try await ProjectSummaryClient.generateProjectSummary(projectId: projectId, accessToken: token)
            project = try await StorageService.updateProject(projectId, fields: ["notes": .string(summary)])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startRecording() async {
        isStartingRecording = true
        defer { isStartingRecording = false }
        let hasKeys = await recordingManager.checkHasKeys()
        guard hasKeys else {
            showKeysAlert = true
            return
        }
        do {
            try await recordingManager.startRecording(projectId: projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
