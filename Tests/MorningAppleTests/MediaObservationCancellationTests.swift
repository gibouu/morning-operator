import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import MorningApple

@Suite("Bounded local OCR")
struct MediaObservationCancellationTests {
    @Test("A deadline returns before a non-cooperative native worker, rejects another service, and discards the late result")
    func deadlineDoesNotWaitForNativeCompletion() async throws {
        let native = OCRTestGate(), timer = OCRTestGate(), replacement = OCRTestGate()
        let lane = MediaOCRLane(sleep: { _ in await timer.wait() })
        let first = MediaObservationService(ocr: lane, recognize: { _ in
            await native.wait()
            return Self.text("Old image")
        })
        let second = MediaObservationService(ocr: lane, recognize: { _ in
            await replacement.wait()
            return Self.text("New image")
        })
        let image = try makeImage()
        let task = Task { try await first.recognizeFrame(in: image) }
        try await waitForCalls(native, 1)
        try await waitForCalls(timer, 1)
        await timer.release(1)
        await #expect(throws: MediaObservationError.ocrTimedOut) { try await task.value }
        #expect(await lane.hasPendingRequest)
        await #expect(throws: MediaObservationError.ocrStillFinishing) {
            try await second.recognizeFrame(in: image)
        }
        #expect(await replacement.calls == 0)
        await native.release(1)
        try await waitForIdle(lane)

        let next = Task { try await second.recognizeFrame(in: image) }
        try await waitForCalls(replacement, 1)
        await replacement.release(1)
        let nextResult = try await next.value
        #expect(nextResult.text == "New image")
        #expect(await native.calls == 1)
        await timer.releaseAll()
    }

    @Test("Cancellation returns while native work ignores it, and keeps the shared slot occupied")
    func cancellationDoesNotWaitForNativeCompletion() async throws {
        let native = OCRTestGate(), timer = OCRTestGate()
        let lane = MediaOCRLane(sleep: { _ in await timer.wait() })
        let service = MediaObservationService(ocr: lane, recognize: { _ in
            await native.wait()
            return Self.text("Cancelled image")
        })
        let image = try makeImage()
        let task = Task { try await service.recognizeFrame(in: image) }
        try await waitForCalls(native, 1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await lane.hasPendingRequest)
        await #expect(throws: MediaObservationError.ocrStillFinishing) {
            try await service.recognizeFrame(in: image)
        }
        #expect(await native.calls == 1)
        await native.release(1)
        try await waitForIdle(lane)
        await timer.releaseAll()
    }

    @Test("An old deadline cannot cancel the next image and successful evidence is preserved")
    func staleDeadlineCannotFinishNewRequest() async throws {
        let native = OCRTestGate(), timer = OCRTestGate()
        let lane = MediaOCRLane(sleep: { _ in await timer.wait() })
        let expected = RecognizedFrameText(text: "Exact source\nSecond line", lines: [], warnings: ["Synthetic warning"])
        let service = MediaObservationService(ocr: lane, recognize: { _ in
            await native.wait()
            return expected
        })
        let image = try makeImage()
        let first = Task { try await service.recognizeFrame(in: image) }
        try await waitForCalls(native, 1)
        try await waitForCalls(timer, 1)
        await native.release(1)
        let result = try await first.value
        #expect(result.text == expected.text && result.lines == expected.lines && result.warnings == expected.warnings)

        let second = Task { try await service.recognizeFrame(in: image) }
        try await waitForCalls(native, 2)
        // This timer deliberately ignores cancellation, just like the native test worker.
        await timer.release(1)
        await native.release(2)
        let secondResult = try await second.value
        #expect(secondResult.text == expected.text)
        await timer.releaseAll()
    }

    @Test("An already cancelled request never enters the native worker")
    func cancelledBeforeStartDoesNotOccupyLane() async throws {
        let start = OCRTestGate(), native = OCRTestGate()
        let lane = MediaOCRLane()
        let task = Task {
            await start.wait()
            return try await lane.perform {
                await native.wait()
                return Self.text("Must not run")
            }
        }
        try await waitForCalls(start, 1)
        task.cancel()
        await start.release(1)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await native.calls == 0)
        #expect(await lane.hasPendingRequest == false)
        let recovered = try await lane.perform { Self.text("Current image") }
        #expect(recovered.text == "Current image")
    }

    @Test("A movie stops at its first OCR timeout instead of treating the remaining samples as failed evidence")
    func movieTimeoutAbandonsExtraction() async throws {
        let source = try await makeMovie()
        defer { try? FileManager.default.removeItem(at: source) }
        let native = OCRTestGate(), timer = OCRTestGate()
        let lane = MediaOCRLane(sleep: { _ in await timer.wait() })
        let service = MediaObservationService(ocr: lane, recognize: { _ in
            await native.wait()
            return Self.text("Too late")
        })
        let extraction = Task { try await service.extract(from: source) }
        try await waitForCalls(native, 1)
        try await waitForCalls(timer, 1)
        await timer.release(1)
        await #expect(throws: MediaObservationError.ocrTimedOut) { try await extraction.value }
        #expect(await native.calls == 1)
        #expect(await lane.hasPendingRequest)
        // The late worker needs only the decoded image, not continued file access.
        try FileManager.default.removeItem(at: source)
        await native.release(1)
        try await waitForIdle(lane)
    }

    private static func text(_ text: String) -> RecognizedFrameText {
        .init(text: text, lines: [], warnings: [])
    }

    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 16, height: 16,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    private func waitForCalls(_ gate: OCRTestGate, _ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await gate.calls < count {
            guard ContinuousClock.now < deadline else { throw OCRTestFailure.milestoneNotReached }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func waitForIdle(_ lane: MediaOCRLane) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await lane.hasPendingRequest {
            guard ContinuousClock.now < deadline else { throw OCRTestFailure.milestoneNotReached }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeMovie() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
            writer.add(input)
            let started = writer.startWriting()
            try #require(started)
            writer.startSession(atSourceTime: .zero)
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer)
            try #require(status == kCVReturnSuccess)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let bytes = CVPixelBufferGetBaseAddress(pixels) {
                memset(bytes, 0, CVPixelBufferGetDataSize(pixels))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            // Two tiny encoded frames span 48 seconds, requesting the real 24-sample loop.
            for second in [0.0, 47.9] {
                let deadline = ContinuousClock.now.advanced(by: .seconds(10))
                while !input.isReadyForMoreMediaData {
                    guard ContinuousClock.now < deadline else { throw OCRTestFailure.milestoneNotReached }
                    try await Task.sleep(for: .milliseconds(5))
                }
                let appended = adaptor.append(pixels, withPresentationTime: CMTime(seconds: second, preferredTimescale: 600))
                try #require(appended)
            }
            writer.endSession(atSourceTime: CMTime(seconds: 48, preferredTimescale: 600))
            input.markAsFinished()
            await writer.finishWriting()
            try #require(writer.status == .completed)
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

/// Deliberately does not observe Task cancellation, matching a stalled native call.
private actor OCRTestGate {
    private(set) var calls = 0
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    func wait() async {
        calls += 1
        let call = calls
        await withCheckedContinuation { pending[call] = $0 }
    }
    func release(_ call: Int) { pending.removeValue(forKey: call)?.resume() }
    func releaseAll() {
        let current = Array(pending.values)
        pending.removeAll()
        for continuation in current { continuation.resume() }
    }
}

private enum OCRTestFailure: Error { case milestoneNotReached }
