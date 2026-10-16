import SwiftUI
import UniformTypeIdentifiers
import MorningCore
import MorningApple

/// Settings can push this view for native file transfer. It is deliberately absent
/// from the Learn / Routine entry destination. Import remains review → draft → approve.
struct MorningRoutineDataView: View {
    @Bindable var store: MorningStore
    /// Keep pending starts/capture processing queued while a transfer is open.
    var onInteractionChanged: (Bool) -> Void = { _ in }
    @ViewState<RoutineVersion?> private var exportSnapshot = nil
    @ViewState<Bool> private var importing = false
    @ViewState<UUID?> private var importGeneration = nil
    @ViewState<RoutineImportPreview?> private var importPreview = nil
    @ViewState<RoutineImportPreview?> private var loadedImport = nil
    @ViewState<Bool> private var importLoading = false
    @ViewState<String?> private var importError = nil
    @ViewState<Task<Void, Never>?> private var importTask = nil
    @ViewState<UUID?> private var importAttempt = nil
    @ViewState<Bool> private var isVisible = false

    private var isInteracting: Bool {
        importing || importLoading || importPreview != nil || exportSnapshot != nil
    }

    var body: some View {
        let pickerGeneration = importGeneration
        MorningList {
            if let routine = store.routine {
                Section {
                    Button("Export routine", systemImage: "square.and.arrow.up") { exportSnapshot = routine }
                        .disabled(importLoading || store.privacyBlocksWork)
                        .accessibilityIdentifier("routine.export")
                }
            }
            Section {
                Button("Import routine", systemImage: "square.and.arrow.down") {
                    guard !store.privacyBlocksWork else { return }
                    importGeneration = store.dataGeneration
                    importing = true
                }
                .disabled(store.busy || store.sessionActive || importLoading || store.privacyBlocksWork)
                .accessibilityIdentifier("routine.import")
                #if DEBUG
                if let url = routineImportFixtureURL {
                    Button("Open staged routine file") { openRoutineFile(url, generation: store.dataGeneration) }
                        .disabled(store.busy || store.sessionActive || importLoading || store.privacyBlocksWork)
                        .accessibilityIdentifier("routine.importFixture")
                }
                #endif
                if importLoading { ProgressView("Opening your routine…") }
                if let importError {
                    Text(importError).font(.footnote).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("routine.importError")
                }
            } footer: {
                Text("Open a saved MORE plan and review it before making any changes. Import saves a draft; approval stays separate.")
            }
        }
        .navigationTitle("Routine files").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportSnapshot) { routine in RoutineExportView(routine: routine) }
        .sheet(item: $importPreview) { preview in
            RoutineImportView(document: preview.document, onUse: { document in
                guard preview.generation == store.dataGeneration, !store.privacyBlocksWork,
                      store.useImportedRoutine(document, replacing: preview.baseRoutine) else { return false }
                importPreview = nil
                return true
            }, errorMessage: { store.notice }, onCancel: { importPreview = nil })
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            guard let pickerGeneration, pickerGeneration == store.dataGeneration,
                  !store.privacyBlocksWork else { return }
            importGeneration = nil
            switch result {
            case .success(let urls): if let url = urls.first { openRoutineFile(url, generation: pickerGeneration) }
            case .failure(let error): importError = error.moreDescription
            }
        }
        .onChange(of: importing) { _, presenting in if !presenting { presentLoadedImport() } }
        .onAppear {
            isVisible = true
            onInteractionChanged(isInteracting)
        }
        .onChange(of: isVisible && isInteracting) { _, value in onInteractionChanged(value) }
        .onChange(of: store.dataGeneration) { _, _ in
            exportSnapshot = nil
            importGeneration = nil
            importing = false
            importAttempt = nil
            importPreview = nil
            loadedImport = nil
            importLoading = false
            importError = nil
            importTask?.cancel()
            importTask = nil
        }
        .onDisappear {
            isVisible = false
            onInteractionChanged(false)
            importAttempt = nil
            loadedImport = nil
            importLoading = false
            importTask?.cancel()
            importTask = nil
        }
    }

    private func openRoutineFile(_ url: URL, generation: UUID) {
        guard generation == store.dataGeneration, !store.privacyBlocksWork,
              !store.busy, !store.sessionActive, !importLoading else { return }
        let attempt = UUID()
        let base = store.routine
        importAttempt = attempt
        importLoading = true
        importError = nil
        importTask = Task { @MainActor in
            do {
                let document = try await RoutineDocumentReader().read(url)
                guard !Task.isCancelled, importAttempt == attempt, store.dataGeneration == generation, !store.privacyBlocksWork else { return }
                loadedImport = RoutineImportPreview(document: document, baseRoutine: base, generation: generation)
                presentLoadedImport()
            } catch {
                guard !Task.isCancelled, importAttempt == attempt, store.dataGeneration == generation, !store.privacyBlocksWork else { return }
                importLoading = false
                importError = AppLanguage.localized("This file couldn't be opened: \(error.moreDescription) Your current routine is unchanged.")
            }
            importTask = nil
        }
    }

    private func presentLoadedImport() {
        guard !store.privacyBlocksWork, !importing, exportSnapshot == nil,
              let loadedImport, loadedImport.generation == store.dataGeneration else { return }
        self.loadedImport = nil
        importLoading = false
        importPreview = loadedImport
    }

    #if DEBUG
    private var routineImportFixtureURL: URL? {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("--ui-testing"), process.environment["MO_ROUTINE_IMPORT_TEST"] == "1",
              let workspace = process.arguments.first(where: { $0.hasPrefix("--ui-testing-workspace=") }),
              UUID(uuidString: String(workspace.dropFirst("--ui-testing-workspace=".count))) != nil,
              let path = process.environment["MO_ROUTINE_IMPORT_FILE"], !path.isEmpty else { return nil }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path)
            : FileManager.default.temporaryDirectory.appendingPathComponent(path)
    }
    #endif
}

private struct RoutineImportPreview: Identifiable {
    let id = UUID()
    let document: PortableRoutineDocument
    let baseRoutine: RoutineVersion?
    let generation: UUID
}
