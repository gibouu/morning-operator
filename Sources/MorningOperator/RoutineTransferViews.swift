import Foundation
import SwiftUI
import UniformTypeIdentifiers
import MorningCore

/// Encodes a previously reviewed portable snapshot, never the current live workspace.
struct PortableRoutineFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    private let encodedData: Data

    init(document: PortableRoutineDocument) throws {
        encodedData = try document.encoded()
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let document = try PortableRoutineDocument.decode(data)
        encodedData = try document.encoded()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: encodedData)
    }
}

/// The caller presents a new sheet for each export. State pins the reviewed routine
/// even if the parent refreshes while this sheet or the system file picker is open.
struct RoutineExportView: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState<RoutineVersion> private var routineSnapshot: RoutineVersion
    @ViewState<Bool> private var includeNotes = false
    @ViewState<Bool> private var showingFileExporter = false
    @ViewState<PortableRoutineFileDocument?> private var preparedFile = nil
    @ViewState<String?> private var statusMessage = nil
    @ViewState<Bool> private var statusIsError = false

    init(routine: RoutineVersion) {
        _routineSnapshot = ViewState(initialValue: routine)
    }

    private var previewResult: Result<PortableRoutineDocument, Error> {
        Result {
            try PortableRoutineDocument(routine: routineSnapshot,
                detail: includeNotes ? .includeDetails : .planOnly)
        }
    }

    var body: some View {
        let preview = previewResult
        NavigationStack {
            MorningList {
                Section {
                    Text(includeNotes ? "Your plan and its notes" : "Your plan only")
                        .font(.serif(.headline))
                    Text("Review the names and text below before saving a file. Names can contain personal information.")
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    Toggle("Include notes", isOn: $includeNotes)
                        .disabled(showingFileExporter)
                        .accessibilityIdentifier("export.includeNotes")
                } footer: {
                    Text(includeNotes
                        ? "Notes and the source label are included exactly as saved. They may contain personal details or quotations from observations."
                        : "Notes, evidence quotations in notes, and the source label are left out.")
                }

                switch preview {
                case .success(let document):
                    RoutineTransferPreview(document: document, prefix: "export")
                case .failure(let error):
                    Section {
                        Label("This routine couldn't be prepared for export", systemImage: "exclamationmark.circle")
                            .font(.serif(.headline))
                        Text(error.localizedDescription).font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    }.accessibilityIdentifier("export.validationError")
                }

                Section {
                    Text("Recordings, observation history, saved choices and app operations aren't included.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                }
                if let statusMessage {
                    Section {
                        Label(statusMessage, systemImage: statusIsError ? "exclamationmark.circle" : "checkmark.circle")
                            .font(.raleway(.subheadline))
                            .accessibilityIdentifier("export.status")
                    }
                }
            }
            .accessibilityIdentifier("export.preview")
            .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
            .navigationTitle("Export routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(showingFileExporter)
                        .accessibilityIdentifier("export.cancel")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    prepareExport()
                } label: {
                    Label("Save file…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(showingFileExporter || !canExport(preview))
                .accessibilityIdentifier("export.save")
                .padding(20).background(.regularMaterial)
            }
            .fileExporter(isPresented: $showingFileExporter, document: preparedFile,
                contentType: .json, defaultFilename: "MORE-Morning-Routine") { result in
                switch result {
                case .success:
                    statusMessage = AppLanguage.localized("Routine exported. Your saved routine hasn't changed.")
                    statusIsError = false
                case .failure(let error):
                    let cocoaError = error as NSError
                    if error is CancellationError ||
                        (cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError) {
                        statusMessage = nil
                        statusIsError = false
                    } else {
                        statusMessage = AppLanguage.localized("The file couldn't be saved. \(error.localizedDescription)")
                        statusIsError = true
                    }
                }
            }
            .onChange(of: includeNotes) { _, _ in
                statusMessage = nil
                statusIsError = false
                preparedFile = nil
            }
        }
    }

    private func canExport(_ result: Result<PortableRoutineDocument, Error>) -> Bool {
        if case .success = result { return true }
        return false
    }

    private func prepareExport() {
        statusMessage = nil
        statusIsError = false
        do {
            // Read exactly the same immutable source and scope as the visible preview.
            let document = try previewResult.get()
            preparedFile = try PortableRoutineFileDocument(document: document)
            showingFileExporter = true
        } catch {
            preparedFile = nil
            statusMessage = AppLanguage.localized("The file couldn't be prepared. \(error.localizedDescription)")
            statusIsError = true
        }
    }
}

/// File access and bounded decoding belong to the caller. The parent owns dismissal;
/// a failed adoption keeps this snapshot visible and leaves the current routine intact.
struct RoutineImportView: View {
    @ViewState<PortableRoutineDocument> private var documentSnapshot: PortableRoutineDocument
    @ViewState<String?> private var failureMessage = nil
    let onUse: @MainActor (PortableRoutineDocument) -> Bool
    let errorMessage: @MainActor () -> String?
    let onCancel: @MainActor () -> Void

    init(document: PortableRoutineDocument,
         onUse: @escaping @MainActor (PortableRoutineDocument) -> Bool,
         errorMessage: @escaping @MainActor () -> String?,
         onCancel: @escaping @MainActor () -> Void) {
        _documentSnapshot = ViewState(initialValue: document)
        self.onUse = onUse
        self.errorMessage = errorMessage
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            MorningList {
                Section {
                    Text("Review this plan before using it")
                        .font(.serif(.headline))
                    Text("This becomes your current draft. An approved routine can be restored while you review. Approve the draft before starting a morning.")
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    Text("Every imported moment is user-led. No app operation is enabled.")
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                }
                RoutineTransferPreview(document: documentSnapshot, prefix: "import")
                Section {
                    Text("This file doesn't add recordings, observation history or saved choices. Your existing saved choices stay separate.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    if documentSnapshot.detail == .planOnly {
                        Text("This plan-only file has no notes or source label.")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                }
                if let failureMessage {
                    Section {
                        Label(failureMessage, systemImage: "exclamationmark.circle")
                            .font(.raleway(.subheadline))
                            .accessibilityIdentifier("import.error")
                    }
                }
            }
            .accessibilityIdentifier("import.preview")
            .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
            .navigationTitle("Import routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("import.cancel")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    failureMessage = nil
                    if !onUse(documentSnapshot) {
                        failureMessage = errorMessage() ?? AppLanguage.localized("The draft couldn't be saved. Your current routine is unchanged.")
                    }
                } label: {
                    Label("Use as a draft", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("import.use")
                .padding(20).background(.regularMaterial)
            }
        }
    }
}

/// All exported free text is shown as plain text without abridging or rendering Markdown.
private struct RoutineTransferPreview: View {
    let document: PortableRoutineDocument
    let prefix: String

    var body: some View {
        Section {
            LabeledContent("Source version", value: String(document.sourceRoutineVersion))
                .accessibilityIdentifier("\(prefix).version")
            LabeledContent("Approval when exported", value: document.approvalAtExport ? AppLanguage.localized("Approved") : AppLanguage.localized("Draft"))
                .accessibilityIdentifier("\(prefix).approval")
            LabeledContent("Planned time", value: AppLanguage.localized("\(document.steps.reduce(0) { $0 + $1.durationMinutes }) minutes"))
            if document.sourceIsSynthetic {
                Label("Sample or test plan", systemImage: "sparkles")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("\(prefix).synthetic")
            }
            if let source = document.sourceLabel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source label").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    Text(verbatim: source).textSelection(.enabled)
                        .accessibilityIdentifier("\(prefix).source")
                }
            }
        } header: {
            Text("In this file")
        } footer: {
            Text("Approval here describes the exported version. An imported routine still needs your local review and approval.")
        }
        ForEach(Array(document.steps.enumerated()), id: \.element.id) { index, step in
            Section {
                Text(verbatim: step.title).font(.serif(.headline)).textSelection(.enabled)
                    .accessibilityIdentifier("\(prefix).step.\(index).title")
                LabeledContent(step.kind.displayName, value: AppLanguage.localized("\(step.durationMinutes) minutes planned"))
                    .font(.raleway(.subheadline))
                    .accessibilityIdentifier("\(prefix).step.\(index).minutes")
                if step.isRequired {
                    Label("Marked to keep in this plan", systemImage: "heart")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("\(prefix).step.\(index).required")
                }
                if let notes = step.detail {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        if notes.isEmpty {
                            Text("Empty").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        } else {
                            Text(verbatim: notes).font(.raleway(.subheadline)).textSelection(.enabled)
                                .accessibilityIdentifier("\(prefix).step.\(index).notes")
                        }
                    }
                }
            } header: {
                Text("Moment \(index + 1)")
            }
        }
        Section {
            DisclosureGroup("File information") {
                LabeledContent("Format", value: document.format)
                LabeledContent("Format version", value: String(document.formatVersion))
                LabeledContent("Routine ID", value: document.sourceRoutineID.uuidString)
                LabeledContent("Routine created", value: document.sourceCreatedAt.formatted(date: .abbreviated, time: .standard))
                ForEach(Array(document.steps.enumerated()), id: \.element.id) { index, step in
                    LabeledContent("Moment \(index + 1) ID", value: step.id.uuidString)
                }
            }
            .font(.raleway(.caption)).textSelection(.enabled)
            .accessibilityIdentifier("\(prefix).fileInformation")
        }
    }
}
