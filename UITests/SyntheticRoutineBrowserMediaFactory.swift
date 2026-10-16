import AVFoundation
import CoreVideo
import Foundation

/// Generated input only: no app control, host media, provider or playback receipt.
/// Register this file only in the UI-test target.
@MainActor
enum SyntheticRoutineBrowserMediaFactory {
    static let launchPrefix = "--ui-testing-private-browser-media="

    enum Failure: Error {
        case encoderUnavailable, writerFailed, writerTimedOut, pixelBufferUnavailable
        case invalidVideo, invalidAudio, payloadTooLarge
    }

    static func launchArgument() async throws -> String {
        let data = try JSONEncoder().encode(try await assets())
        guard data.count <= 260_000 else { throw Failure.payloadTooLarge }
        let argument = launchPrefix + data.base64EncodedString()
        guard argument.utf8.count <= 360_000 else { throw Failure.payloadTooLarge }
        return argument
    }

    static func assets() async throws -> [String: Data] {
        try Task.checkCancellation()
        return ["video": try await video(), "music": try music()]
    }

    private static func video() async throws -> Data {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyntheticBrowserMedia-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("generated.mp4")
        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: url, fileType: .mp4) }
        catch { throw Failure.encoderUnavailable }
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let width = 96, height = 64
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 32_000,
                AVVideoExpectedSourceFrameRateKey: 4,
                AVVideoMaxKeyFrameIntervalKey: 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
            ]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ])
        guard writer.canAdd(input) else { throw Failure.encoderUnavailable }
        writer.add(input)
        writer.shouldOptimizeForNetworkUse = true
        guard writer.startWriting() else { throw Failure.writerFailed }
        writer.startSession(atSourceTime: .zero)
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(15))
        for frame in 0..<8 {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw Failure.writerFailed }
                guard clock.now < deadline else { throw Failure.writerTimedOut }
                try await Task.sleep(for: .milliseconds(10))
            }
            try Task.checkCancellation()
            let buffer = try pixels(frame: frame, width: width, height: height)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 4)) else {
                throw Failure.writerFailed
            }
        }
        writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1))
        input.markAsFinished()
        // The callback deliberately captures no actor-isolated state. Poll the
        // writer on its owning actor; neither a delay nor a callback proves output.
        writer.finishWriting(completionHandler: { @Sendable in })
        while writer.status == .writing {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw Failure.writerTimedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
        try Task.checkCancellation()
        guard writer.status == .completed else { throw Failure.writerFailed }
        let data = try Data(contentsOf: url)
        guard (20...120_000).contains(data.count),
              data.dropFirst(4).prefix(4) == Data("ftyp".utf8) else { throw Failure.invalidVideo }
        return data
    }

    private static func pixels(frame: Int, width: Int, height: Int) throws -> CVPixelBuffer {
        var optional: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  nil, &optional) == kCVReturnSuccess,
              let buffer = optional,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else {
            throw Failure.pixelBufferUnavailable
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw Failure.pixelBufferUnavailable }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        // Eight visibly different RGB frames, not a still-image placeholder.
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * stride + x * 4
                let movingSquare = (frame * 10..<(frame * 10 + 16)).contains(x) && (24..<40).contains(y)
                bytes[offset] = movingSquare ? 220 : UInt8(35 + frame * 8)
                bytes[offset + 1] = movingSquare ? 220 : UInt8(80 + y)
                bytes[offset + 2] = movingSquare ? 245 : UInt8(40 + x)
                bytes[offset + 3] = 255
            }
        }
        return buffer
    }

    /// A locally generated four-note sine melody; no recording or licensed asset.
    private static func music() throws -> Data {
        let rate = 22_050, sampleCount = rate * 2, dataBytes = sampleCount * 2
        var data = Data()
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func little<T: FixedWidthInteger>(_ value: T) {
            var bytes = value.littleEndian
            withUnsafeBytes(of: &bytes) { data.append(contentsOf: $0) }
        }
        ascii("RIFF"); little(UInt32(36 + dataBytes)); ascii("WAVEfmt ")
        little(UInt32(16)); little(UInt16(1)); little(UInt16(1)); little(UInt32(rate))
        little(UInt32(rate * 2)); little(UInt16(2)); little(UInt16(16))
        ascii("data"); little(UInt32(dataBytes))
        let frequencies = [330.0, 440.0, 392.0, 523.25]
        for sample in 0..<sampleCount {
            let time = Double(sample) / Double(rate), note = min(3, Int(time * 2))
            let local = time - Double(note) * 0.5
            let envelope = max(0, min(1, min(local / 0.02, (0.5 - local) / 0.02)))
            let value = sin(2 * .pi * frequencies[note] * time) * envelope * 0.12
            little(Int16((value * Double(Int16.max)).rounded()))
        }
        guard data.count == 44 + dataBytes, data.count <= 120_000,
              data.prefix(4) == Data("RIFF".utf8), data.dropFirst(8).prefix(4) == Data("WAVE".utf8) else {
            throw Failure.invalidAudio
        }
        return data
    }
}
