// Records Cubby Test's demo: only that app's windows (so nothing else on the screen gets
// in), without the real pointer, at the display's full resolution, as HEVC.
//
//   swift Scripts/record-demo.swift <output.mov>
//
// Waits for the demo to say it's ready, starts recording, tells it to go, and stops once
// it's finished. Needs Screen Recording permission for whatever runs it.
import AVFoundation
import AppKit
import ScreenCaptureKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "demo.mov")
let bundleID = "com.cubby.app.test"
let ready = Notification.Name("com.cubby.demo.ready")
let go = Notification.Name("com.cubby.demo.go")
let finished = Notification.Name("com.cubby.demo.finished")

func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

final class Recorder: NSObject, SCStreamOutput, @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var started = false
    var frames = 0
    let queue = DispatchQueue(label: "frames")

    init(width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: output)
        writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 80_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete
        else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData {
            input.append(buffer)
            frames += 1
        }
    }

    func finish() async {
        input.markAsFinished()
        await writer.finishWriting()
    }
}

func waitFor(_ name: Notification.Name, timeout: Double) async -> Bool {
    await withCheckedContinuation { continuation in
        let lock = NSLock()
        var done = false
        func resume(_ value: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true
            continuation.resume(returning: value)
        }
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: nil) { _ in resume(true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { resume(false) }
    }
}

let main = Task {
    log("waiting for the demo to be ready…")
    guard await waitFor(ready, timeout: 60) else { log("the demo never got ready"); exit(1) }
    try? await Task.sleep(for: .seconds(1))

    let content: SCShareableContent
    do {
        content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    } catch {
        log("no permission to record the screen: \(error.localizedDescription)")
        log("allow it in System Settings → Privacy & Security → Screen & System Audio Recording")
        exit(2)
    }
    guard let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }),
          let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
    else { log("Cubby Test isn't running"); exit(1) }
    // The menu bar icon is the app's too; leave it out.
    let menuBarItems = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleID && $0.frame.height < 40 }
    let filter = SCContentFilter(display: display, including: [app], exceptingWindows: menuBarItems)

    let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
    let config = SCStreamConfiguration()
    config.width = display.width * scale
    config.height = display.height * scale
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.showsCursor = false
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.queueDepth = 8
    config.colorSpaceName = CGColorSpace.sRGB

    let recorder = try Recorder(width: config.width, height: config.height)
    let stream = SCStream(filter: filter, configuration: config, delegate: nil)
    try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
    try await stream.startCapture()
    log("recording \(config.width)×\(config.height) to \(output.path)")
    try? await Task.sleep(for: .seconds(1))
    DistributedNotificationCenter.default().postNotificationName(go, object: nil, userInfo: nil, deliverImmediately: true)

    let done = await waitFor(finished, timeout: 240)
    if !done { log("the demo didn't finish in time; stopping anyway") }
    try? await Task.sleep(for: .seconds(0.5))
    try await stream.stopCapture()
    await recorder.finish()
    log("done: \(recorder.frames) frames")
    exit(0)
}

RunLoop.main.run()
