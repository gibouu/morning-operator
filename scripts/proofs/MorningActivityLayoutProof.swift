// Appended to the verbatim production island views by prove-activity-layout.sh.
// This stub preserves the production Button and label without app side effects.
private struct AddStepTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add two minutes"
    static let description = IntentDescription("Add two minutes to the current morning step.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Session") var session: String?
    @Parameter(title: "Step") var step: String?
    @Parameter(title: "Displayed end") var expectedEndToken: String?
    init() {}
    init(sessionID: UUID, stepID: UUID, expectedEnd: Date) {
        session = sessionID.uuidString
        step = stepID.uuidString
        expectedEndToken = StepTimer.extensionToken(for: expectedEnd)
    }
    func perform() async throws -> some IntentResult { .result() }
}

// ImageRenderer on macOS intermittently omits the remote AppIntent button host.
// Stub that action host only. This overload keeps the production Button label,
// style, frame, accessibility and surrounding layout unchanged.
private extension Button {
    @MainActor init(intent: AddStepTimeIntent, @ViewBuilder label: () -> Label) {
        self.init(action: {}, label: label)
    }
}

// The running Text(timerInterval:) provider cannot be snapshotted consistently
// by macOS ImageRenderer. Freeze its displayed value at the captured state date.
// Supported French/English use the same positional clock digits and separators.
private func proofFrozenCountdown(timer: MorningActivityStepTimer, state: MorningActivityContentState) -> String {
    let seconds = Int(max(0, timer.endsAt.timeIntervalSince(state.updatedAt)).rounded(.up))
    if seconds >= 3_600 {
        return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

@main
private struct MorningActivityLayoutProof {
    private struct Case {
        let name: String
        let status: MorningActivityStatus
        var stale = false
        var remaining: TimeInterval? = 278
        var destination: StepDestination = .app(.instagram)
        var hasNextStep = true
    }
    private struct Result: Codable {
        let name: String
        let language: String
        let dynamicType: String
        let contentWidth: Double
        let contentHeight: Double
        let heightWithCameraAndBottomReserve: Double
        let expectedText: [String]
        let recognizedText: [String]
        let missingText: [String]
        let fitsHeightBudget: Bool
    }
    private struct SmallResult: Codable {
        let name: String
        let width: Double
        let height: Double
        let recognizedText: [String]
        let fullCountdownVisible: Bool
    }
    private static let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let stepID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileReadInvalidFileName) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        // Initialize AppKit without opening a window or taking the foreground.
        _ = NSApplication.shared
        try verifyProgressDotsGeometry()
        let allCases: [Case] = [
            Case(name: "running", status: .running),
            Case(name: "attention", status: .needsAttention),
            Case(name: "running-maximum-finish", status: .running, remaining: 1_500 * 60,
                 destination: .connectedService, hasNextStep: false),
            Case(name: "paused-long-destination", status: .paused, destination: .inMORE(.instagram)),
            Case(name: "paused-maximum-finish", status: .paused, remaining: 1_500 * 60,
                 destination: .connectedService, hasNextStep: false),
            Case(name: "stale-timer", status: .needsAttention, stale: true),
            Case(name: "stale-no-timer", status: .running, stale: true, remaining: nil)
        ]
        let selectedNames = ProcessInfo.processInfo.environment["MO_ACTIVITY_PROOF_CASES"]?
            .split(separator: ",").map(String.init)
        let cases = selectedNames.map { names in allCases.filter { names.contains($0.name) } } ?? allCases
        guard !cases.isEmpty, selectedNames?.allSatisfy({ name in allCases.contains { $0.name == name } }) ?? true else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        var results: [Result] = []
        for language in ["fr", "en"] {
            // Deliberately choose the opposite app language. Snapshot localization
            // must remain correct across the widget's separate process boundary.
            AppLanguage.setChosenLanguage(language == "fr" ? "en" : "fr")
            for width in [315.0, 352.0] {
                for (typeName, typeSize) in [("large", DynamicTypeSize.large), ("xxxLarge", .xxxLarge)] {
                    for item in cases {
                        results.append(try render(item, language: language, width: width,
                                                  typeName: typeName, typeSize: typeSize, output: output))
                    }
                }
            }
        }
        let smallResults = try renderSmallComponents(output: output)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: output.appendingPathComponent("measurements.json"))
        try encoder.encode(smallResults).write(to: output.appendingPathComponent("small-measurements.json"))
        let failures = results.filter { !$0.fitsHeightBudget || !$0.missingText.isEmpty }
        let smallFailures = smallResults.filter { !$0.fullCountdownVisible }
        let maximumHeight = results.map(\.heightWithCameraAndBottomReserve).max() ?? 0
        let notes = """
        # Native macOS Live Activity component proof

        This renders the current production MorningActivityIslandDetail and all of its private child views, copied at run time. The app-bound AddStepTimeIntent is inert. A proof-only exact-type Button initializer replaces its remote action host with an empty action because macOS ImageRenderer can omit that host. The running Text(timerInterval:) and ProgressView(timerInterval:) providers are frozen at the captured state date because their live invalidations cause incomplete offscreen renders. The production label, font, style, frame, accessibility and layout stay unchanged. The two real string catalogs are compiled. Each activity language is tested while the app language is set to the opposite choice.

        Selected cases: \(cases.map(\.name).joined(separator: ", ")). Set MO_ACTIVITY_PROOF_CASES to a comma-separated list to choose a focused run; omit it for the full matrix.

        Rendered \(results.count) expanded cases selected above, in French/English, at content widths 315/352pt and requested Dynamic Type large/xxxLarge. Timer fixtures use 4:38 or the maximum 1500 minutes. A 36pt camera reserve and 14pt bottom reserve are added to measured natural component height. The component images are unmasked so clipping cannot conceal overflow. Native Vision OCR checks full status, destination and action labels. Additional images render the real compact timer at 52x22pt with its complete maximum running/paused countdown, plus the 22x22pt minimal mark.

        Maximum height including the reserves: \(String(format: "%.1f", maximumHeight))pt. Failing expanded cases: \(failures.count). Failing compact countdown cases: \(smallFailures.count).

        Limits: macOS system fonts and Dynamic Type metrics differ from iOS. This is component layout and localization evidence, not actual ActivityKit safe-area, curved mask, limited-width iOS 27 presentation, timer-ticking, interaction or Simulator acceptance. The image includes no simulated camera or island mask. An iOS Simulator/device visual check remains necessary when a runtime is available.
        """
        try notes.write(to: output.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        for failure in failures {
            print("FAIL \(failure.name): height \(failure.heightWithCameraAndBottomReserve); missing \(failure.missingText)")
        }
        print("\(results.count) expanded native macOS component renders and \(smallResults.count) small component renders; maximum height \(String(format: "%.1f", maximumHeight))pt; \(failures.count + smallFailures.count) failures. Output: \(output.path)")
        if !failures.isEmpty || !smallFailures.isEmpty { exit(1) }
    }

    private static func verifyProgressDotsGeometry() throws {
        let invalid: [CGRect] = [
            .zero, .null, .infinite,
            CGRect(x: 0, y: 0, width: CGFloat.nan, height: 4),
            CGRect(x: 0, y: 0, width: 100, height: CGFloat.infinity),
            CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 4),
            CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
                   width: CGFloat.greatestFiniteMagnitude, height: 4)
        ]
        guard invalid.allSatisfy({ MorningWidgetProgressDots().path(in: $0).isEmpty }) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        for width: CGFloat in [1, 315, 352, .greatestFiniteMagnitude] {
            let path = MorningWidgetProgressDots().path(in: CGRect(x: 0, y: 0, width: width, height: 4))
            guard !path.isEmpty, path.boundingRect.width.isFinite, path.boundingRect.height.isFinite else {
                throw CocoaError(.validationMissingMandatoryProperty)
            }
        }
        print("Progress mask: 7 invalid and 4 finite geometry regression cases passed.")
    }

    @MainActor private static func render(_ item: Case, language: String, width: Double,
                                          typeName: String, typeSize: DynamicTypeSize, output: URL) throws -> Result {
        let now = Date()
        let timer = item.remaining.map {
            MorningActivityStepTimer(stepID: stepID, destination: item.destination,
                endsAt: now.addingTimeInterval($0), nextDestination: .app(.calendar),
                hasNextStep: item.hasNextStep, pausedRemaining: item.status == .paused ? $0 : nil,
                startedAt: now.addingTimeInterval(-22))
        }
        let state = try MorningActivityContentState(category: .entertainment, status: item.status,
            completedSteps: 1, totalSteps: 4, updatedAt: now, stepTimer: timer, languageIdentifier: language)
        let presentation = MorningActivityPresentation(state: state, isStale: item.stale)
        let view = MorningActivityIslandDetail(presentation: presentation, sessionID: sessionID)
            .environment(\.locale, state.locale).environment(\.layoutDirection, .leftToRight)
            .environment(\.dynamicTypeSize, typeSize).environment(\.colorScheme, .dark)
            .frame(width: width).fixedSize(horizontal: false, vertical: true)
        let natural = ImageRenderer(content: view.background(.black))
        natural.scale = 3
        natural.proposedSize = ProposedViewSize(width: width, height: nil)
        guard let naturalImage = natural.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let height = Double(naturalImage.height) / natural.scale
        let renderer = ImageRenderer(content: view.padding(.top, 36).padding(.bottom, 14)
            .padding(.horizontal, 28).background(.black))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: width + 56, height: nil)
        // Let native SwiftUI resolve its first date/control update before capture.
        _ = renderer.cgImage
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              let capturedImage = NSBitmapImageRep(data: png)?.cgImage else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = "\(language)-w\(Int(width))-\(typeName)-\(item.name)"
        try png.write(to: output.appendingPathComponent(name + ".png"))
        var expected = [presentation.status]
        if timer != nil {
            expected += [item.destination.displayName(locale: state.locale), activityText("+2 min", locale: state.locale),
                         item.hasNextStep ? activityText("Next", locale: state.locale) : activityText("Finish", locale: state.locale)]
        } else {
            expected += [activityText("Open MORE to update.", locale: state.locale)]
        }
        var recognized = try recognizedText(in: capturedImage, language: language)
        var text = normalized(recognized.joined(separator: " "))
        if expected.contains(where: { !text.contains(normalized($0)) }) {
            // A large timer can make Vision skip the smaller text around it.
            // Read overlapping quadrants of the same pixels, then retain the
            // untouched image as the review artifact. Missing labels still fail.
            for x in [0.0, 0.3] {
                for y in [0.0, 0.35] {
                    let crop = CGRect(x: Double(capturedImage.width) * x, y: Double(capturedImage.height) * y,
                        width: Double(capturedImage.width) * 0.7, height: Double(capturedImage.height) * 0.65)
                    if let cropped = capturedImage.cropping(to: crop) {
                        recognized += try recognizedText(in: cropped, language: language)
                    }
                }
            }
            let actionsCrop = CGRect(x: Double(capturedImage.width) * 0.5, y: Double(capturedImage.height) * 0.35,
                width: Double(capturedImage.width) * 0.5, height: Double(capturedImage.height) * 0.65)
            if let cropped = capturedImage.cropping(to: actionsCrop) {
                recognized += try recognizedText(in: cropped, language: language)
            }
            let captionsCrop = CGRect(x: Double(capturedImage.width) * 0.5, y: Double(capturedImage.height) * 0.68,
                width: Double(capturedImage.width) * 0.5, height: Double(capturedImage.height) * 0.18)
            if let cropped = capturedImage.cropping(to: captionsCrop) {
                recognized += try recognizedText(in: cropped, language: language)
            }
            text = normalized(recognized.joined(separator: " "))
        }
        let missing = expected.filter { !text.contains(normalized($0)) }
        return Result(name: name, language: language, dynamicType: typeName, contentWidth: width,
            contentHeight: height, heightWithCameraAndBottomReserve: height + 50,
            expectedText: expected, recognizedText: recognized, missingText: missing,
            fitsHeightBudget: height + 50 <= 160)
    }

    @MainActor private static func renderSmallComponents(output: URL) throws -> [SmallResult] {
        var results: [SmallResult] = []
        let now = Date()
        for language in ["fr", "en"] {
          for status in [MorningActivityStatus.paused, .running] {
            let timer = MorningActivityStepTimer(stepID: stepID, destination: .app(.instagram),
                endsAt: now.addingTimeInterval(90_000), nextDestination: nil, hasNextStep: false,
                pausedRemaining: status == .paused ? 90_000 : nil, startedAt: now.addingTimeInterval(-22))
            let state = try MorningActivityContentState(category: .entertainment, status: status,
                completedSteps: 1, totalSteps: 4, updatedAt: now, stepTimer: timer, languageIdentifier: language)
            for (typeName, typeSize) in [("large", DynamicTypeSize.large), ("xxxLarge", .xxxLarge)] {
                let view = MorningActivityCompactTimer(timer: timer, state: state)
                    .environment(\.locale, state.locale).environment(\.dynamicTypeSize, typeSize)
                    .environment(\.layoutDirection, .leftToRight).frame(width: 52, height: 22).background(.black)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 6
                guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
                let name = "\(language)-compact-52-\(typeName)-maximum-\(status.rawValue)"
                let capturedImage = try save(image, to: output.appendingPathComponent(name + ".png"))
                let recognized = try recognizedText(in: capturedImage, language: language)
                let full = status == .paused ? normalized(recognized.joined()).contains("150000") :
                    recognized.contains { $0.range(of: "(?:24:59:[0-5][0-9]|25:00:00)", options: .regularExpression) != nil }
                results.append(SmallResult(name: name, width: Double(image.width) / 6,
                    height: Double(image.height) / 6, recognizedText: recognized, fullCountdownVisible: full))
            }
          }
        }
        let minimal = ImageRenderer(content: MorningWidgetLivingMark(fraction: 0.4)
            .foregroundStyle(MorningActivityPalette.islandAccent).frame(width: 22, height: 22).background(.black))
        minimal.scale = 6
        guard let image = minimal.cgImage else { throw CocoaError(.fileWriteUnknown) }
        try save(image, to: output.appendingPathComponent("minimal-mark-22.png"))
        return results
    }

    @discardableResult private static func save(_ image: CGImage, to url: URL) throws -> CGImage {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              let capturedImage = NSBitmapImageRep(data: png)?.cgImage else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
        return capturedImage
    }

    private static func recognizedText(in image: CGImage, language: String) throws -> [String] {
        let request = VNRecognizeTextRequest()
        // The host's ANE OCR service can stall (#204). Keep this small local
        // proof on the CPU so it does not depend on that service.
        request.usesCPUOnly = true
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [language == "fr" ? "fr-FR" : "en-US"]
        request.usesLanguageCorrection = false
        // Vision must read the same flattened pixels as the delivered PNG. A
        // renderer CGImage can retain lazy drawing for date-based SwiftUI text.
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try VNImageRequestHandler(data: png).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            .unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }
}
