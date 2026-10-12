import Foundation

@MainActor
private enum UITestObservationLaunch {
    static var handled = false
}

extension MorningStore {
    /// Exercises the real importer only in an explicitly isolated UI-test workspace.
    /// Synthetic notes and blank fault-test movies are never evidence of screen capture.
    func importUITestObservationIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              (arguments.contains("--ui-testing-import-observation") || arguments.contains("--ui-testing-import-recorded-video")
               || arguments.contains("--ui-testing-import-blank-video")),
              let workspaceID = arguments.first(where: { $0.hasPrefix("--ui-testing-workspace=") })
                .flatMap({ UUID(uuidString: String($0.dropFirst("--ui-testing-workspace=".count))) }),
              !UITestObservationLaunch.handled else { return }
        UITestObservationLaunch.handled = true

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MorningOperatorUITests-\(workspaceID.uuidString)", isDirectory: true)
        if arguments.contains("--ui-testing-import-blank-video") {
            // A controller-staged, deliberately blank movie exercises failed extraction.
            // Missing media must fail this path, never fall through to the synthetic note.
            let file = directory.appendingPathComponent("BlankObservation.mov")
            guard FileManager.default.fileExists(atPath: file.path) else {
                notice = "Blank fault-test video is missing from the isolated workspace."
                return
            }
            importObservation(file)
            return
        }
        if arguments.contains("--ui-testing-import-recorded-video") {
            // The controller copies a finalized simulator recording into this isolated
            // workspace. Missing media is a failure; never substitute generated notes.
            let file = directory.appendingPathComponent("RecordedObservation.mov")
            guard FileManager.default.fileExists(atPath: file.path) else {
                notice = "Recorded UI-test video is missing from the isolated workspace."
                return
            }
            importObservation(file)
            return
        }
        let file = directory.appendingPathComponent("UITestSyntheticObservation.txt")
        let text = "[Synthetic UI-test observation]\nI check my calendar, drink water, and enjoy ten minutes of chess."
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            importObservation(file)
        } catch {
            notice = "Synthetic UI-test observation import failed: \(error.localizedDescription)"
        }
    }
}
