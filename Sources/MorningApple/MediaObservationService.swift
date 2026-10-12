import AVFoundation
import Foundation
import ImageIO
import MorningCore
import UniformTypeIdentifiers
import Vision

public struct MediaObservation: Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable { case image, video, text }
    public let kind: Kind
    public let text: String
    public let sampledFrameCount: Int
    public let durationSeconds: Double?
    public let warnings: [String]
    /// Present only for videos. Every requested frame survives here before notes deduplication.
    public let videoEvidence: ObservationVideoEvidence?
    public var hasRecognizedText: Bool {
        videoEvidence?.hasRecognizedText ?? !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum MediaObservationError: LocalizedError, Sendable, Equatable {
    case localFileRequired
    case unsupportedFormat
    case fileTooLarge
    case unreadableImage
    case unreadableText
    case invalidVideoDuration
    case videoTooLong(maximumMinutes: Int)
    case noRecognizableText

    public var errorDescription: String? {
        switch self {
        case .localFileRequired: String(localized: "Choose a local file using the import picker.", bundle: .module)
        case .unsupportedFormat: String(localized: "Choose a screenshot, a video, or a UTF-8 text/Markdown file.", bundle: .module)
        case .fileTooLarge: String(localized: "This file exceeds the prototype's 512 MB limit. Export a shorter recording first.", bundle: .module)
        case .unreadableImage: String(localized: "This image could not be decoded. Try a PNG or JPEG screenshot.", bundle: .module)
        case .unreadableText: String(localized: "This text file could not be read as UTF-8, or exceeds the 32,000-character import limit.", bundle: .module)
        case .invalidVideoDuration: String(localized: "This video has no readable finite duration. Try another recording.", bundle: .module)
        case .videoTooLong(let maximum): String(localized: "Choose a recording shorter than \(maximum) minutes for this prototype.", bundle: .module)
        case .noRecognizableText: String(localized: "No readable screen text was found. The image may be blank, protected, or too small. You can describe the routine in your own words.", bundle: .module)
        }
    }
}

/// One Vision pass returns the unchanged flattened text and optional layout for its exact spans.
/// Bounds are approximate Vision guidance, not proof of a physical line or an app/title role.
struct RecognizedFrameText: Sendable {
    let text: String
    let lines: [ObservationOCRLine]
    let warnings: [String]
}

/// Reads only the explicitly supplied file. Nothing is uploaded. The caller owns returned evidence.
public actor MediaObservationService {
    public typealias ProgressHandler = @MainActor @Sendable (Double) -> Void
    public static let maximumFileBytes = 512 * 1_024 * 1_024
    // Allow a minute of writer/stop finalization around the longest 30-minute recording preset.
    public static let maximumVideoSeconds = ObservationVideoEvidence.maximumDurationSeconds
    public static let maximumFrames = ObservationVideoEvidence.maximumFrames

    public init() {}

    public func extractText(from url: URL, progress: ProgressHandler? = nil) async throws -> String {
        let observation = try await extract(from: url, progress: progress)
        guard observation.hasRecognizedText else { throw MediaObservationError.noRecognizableText }
        return observation.text
    }

    public func extract(from url: URL, progress: ProgressHandler? = nil) async throws -> MediaObservation {
        guard url.isFileURL else { throw MediaObservationError.localFileRequired }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw MediaObservationError.localFileRequired }
        guard (values.fileSize ?? Int.max) <= Self.maximumFileBytes else { throw MediaObservationError.fileTooLarge }
        await progress?(0)
        // LaunchServices metadata may be unavailable in a test runner or restricted process.
        // File access/size checks still apply; decoders validate any extension-based fallback.
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        let extensionName = url.pathExtension.lowercased()

        if type?.conforms(to: .image) == true || ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp"].contains(extensionName) {
            let recognized = try await recognizeFrame(in: Self.thumbnail(from: url))
            guard !recognized.text.isEmpty else { throw MediaObservationError.noRecognizableText }
            await progress?(1)
            return MediaObservation(
                kind: .image,
                text: "[User-selected screenshot; one moment, not a confirmed habit]\n\(recognized.text)",
                sampledFrameCount: 1, durationSeconds: nil, warnings: recognized.warnings, videoEvidence: nil
            )
        }
        if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true || ["mp4", "mov", "m4v"].contains(extensionName) {
            return try await extractVideo(from: url, progress: progress)
        }
        if type?.conforms(to: .plainText) == true || ["txt", "md", "markdown"].contains(extensionName) {
            guard (values.fileSize ?? Int.max) <= 256_000 else { throw MediaObservationError.unreadableText }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8), text.count <= 32_000 else {
                throw MediaObservationError.unreadableText
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MediaObservationError.noRecognizableText
            }
            try Task.checkCancellation()
            await progress?(1)
            return MediaObservation(kind: .text, text: text, sampledFrameCount: 0, durationSeconds: nil, warnings: [], videoEvidence: nil)
        }
        throw MediaObservationError.unsupportedFormat
    }

    private func extractVideo(from url: URL, progress: ProgressHandler?) async throws -> MediaObservation {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw MediaObservationError.invalidVideoDuration }
        guard duration <= Self.maximumVideoSeconds else {
            throw MediaObservationError.videoTooLong(maximumMinutes: Int(Self.maximumVideoSeconds / 60))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1_920, height: 1_920)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
        defer { generator.cancelAllCGImageGeneration() }

        let times = FrameSampling.timestamps(duration: duration, maximumFrames: Self.maximumFrames)
        var builder = try VideoObservationBuilder(durationSeconds: duration)
        for (index, seconds) in times.enumerated() {
            try Task.checkCancellation()
            let sampleID = UUID()
            let decoded: (image: CGImage, actualTime: CMTime)
            do {
                let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
                decoded = (frame.image, frame.actualTime)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                try builder.append(id: sampleID, requestedTimeSeconds: seconds, actualTimeSeconds: nil, outcome: .decodeFailed)
                await progress?(Double(index + 1) / Double(times.count))
                continue
            }
            // Convert metadata outside the image-decode catch. Unsupported native timing
            // cannot relabel a successfully decoded image as a decode failure.
            let timing = DecodedFrameTiming(decoded.actualTime)
            let recognized: RecognizedFrameText
            do {
                recognized = try await recognizeFrame(in: decoded.image)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                try builder.append(id: sampleID, requestedTimeSeconds: seconds,
                                   actualTimeSeconds: timing.seconds, outcome: .ocrFailed,
                                   ocrWarnings: timing.warnings, originalPresentationTime: timing.original)
                await progress?(Double(index + 1) / Double(times.count))
                continue
            }
            try builder.append(id: sampleID, requestedTimeSeconds: seconds, actualTimeSeconds: timing.seconds,
                               outcome: recognized.text.isEmpty ? .blank : .observed, text: recognized.text,
                               ocrLines: recognized.lines, ocrWarnings: recognized.warnings + timing.warnings,
                               originalPresentationTime: timing.original)
            await progress?(Double(index + 1) / Double(times.count))
        }
        try Task.checkCancellation()
        let evidence = try builder.finish()
        return MediaObservation(
            kind: .video,
            text: evidence.renderedText,
            sampledFrameCount: evidence.decodedFrameCount,
            durationSeconds: duration,
            warnings: evidence.warnings,
            videoEvidence: evidence
        )
    }

    /// Internal so a synthetic-image test can inspect the exact native result used by video extraction.
    func recognizeFrame(in image: CGImage) async throws -> RecognizedFrameText {
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        let ordered = observations.sorted { left, right in
            let leftRow = Int((left.topLeft.y * 80).rounded())
            let rightRow = Int((right.topLeft.y * 80).rounded())
            if leftRow != rightRow { return leftRow > rightRow }
            return left.topLeft.x < right.topLeft.x
        }
        var parts: [String] = []
        var lines: [ObservationOCRLine] = []
        var characterOffset = 0
        var unavailableLayoutCount = 0
        var cappedLayoutCount = 0
        for observation in ordered {
            try Task.checkCancellation()
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.25 else { continue }
            let original = candidate.string
            // Preserve the pre-existing flattened OCR contract, including its trimming and order.
            let text = original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if !parts.isEmpty { characterOffset += 1 }
            let start = characterOffset
            parts.append(text)
            characterOffset += text.count
            guard lines.count < ObservationFrameEvidence.maximumOCRLines else {
                cappedLayoutCount += 1
                continue
            }
            let range = Self.trimmedRange(in: original)
            // Do not search for or normalize a different occurrence of the candidate text.
            guard String(original[range]).utf8.elementsEqual(text.utf8),
                  let rectangle = candidate.boundingBox(for: range) else {
                unavailableLayoutCount += 1
                continue
            }
            // This is the candidate-range box, not observation confidence/region. The
            // axis-aligned enclosing box is approximate character-position guidance.
            let rect = rectangle.boundingBox.cgRect
            do {
                // Vision coordinates remain lower-left normalized in the oriented decoded image.
                // Never clamp invalid geometry or substitute a guessed full-image rectangle.
                let bounds = try ObservationNormalizedBounds(x: Double(rect.origin.x), y: Double(rect.origin.y),
                    width: Double(rect.width), height: Double(rect.height))
                lines.append(try ObservationOCRLine(text: text, startCharacterOffset: start,
                    endCharacterOffset: characterOffset, bounds: bounds, confidence: Double(candidate.confidence)))
            } catch {
                unavailableLayoutCount += 1
            }
        }
        var warnings: [String] = []
        if unavailableLayoutCount > 0 {
            warnings.append(String(localized: "Layout metadata was unavailable or invalid for \(unavailableLayoutCount) OCR regions; their text was preserved.", bundle: .module))
        }
        if cappedLayoutCount > 0 {
            warnings.append(String(localized: "Layout metadata for \(cappedLayoutCount) OCR regions was omitted at the line limit; their text was preserved.", bundle: .module))
        }
        return RecognizedFrameText(text: parts.joined(separator: "\n"), lines: lines, warnings: warnings)
    }

    private static func trimmedRange(in text: String) -> Range<String.Index> {
        let scalars = text.unicodeScalars
        let whitespace = CharacterSet.whitespacesAndNewlines
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, whitespace.contains(scalars[start]) { start = scalars.index(after: start) }
        while start < end {
            let previous = scalars.index(before: end)
            guard whitespace.contains(scalars[previous]) else { break }
            end = previous
        }
        return start..<end
    }

    private static func thumbnail(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_920
              ] as CFDictionary)
        else { throw MediaObservationError.unreadableImage }
        return image
    }
}

enum FrameSampling {
    /// At most one sample every two seconds until the cap; then evenly cover the full video.
    static func timestamps(duration: Double, maximumFrames: Int) -> [Double] {
        guard duration.isFinite, duration > 0, maximumFrames > 0 else { return [] }
        let count = min(maximumFrames, max(1, Int(ceil(min(duration, 86_400) / 2))))
        guard count > 1 else { return [0] }
        let last = max(0, duration - min(0.1, duration / 2))
        return (0..<count).map { last * Double($0) / Double(count - 1) }
    }

    static func timestampLabel(_ seconds: Double) -> String {
        let value = max(0, min(seconds.isFinite ? seconds : 0, 86_400))
        return String(format: "%02d:%04.1f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60))
    }
}

/// Native source-field transfer only. It does not seek, rescale, round, or derive intervals.
struct DecodedFrameTiming: Sendable {
    let seconds: Double
    let original: ObservationMediaTime?
    let warnings: [String]

    init(_ time: CMTime) {
        seconds = time.seconds
        original = try? ObservationMediaTime(value: time.value, timescale: time.timescale,
                                              epoch: time.epoch, flags: time.flags.rawValue)
        warnings = original == nil ? [
            String(localized: "Original media timing could not be preserved; the decoded image and available decimal sample time were retained.", bundle: .module)
        ] : []
    }
}
