// Turns a demo recording into a finished MP4: fills the target size, applies the camera moves recorded in
// IN.camera.json (zooms toward the wheel), keeps the soundtrack.
// swift scripts/export-video.swift IN.mov OUT.mp4 [WIDTH HEIGHT [MBPS]]   (default 1080×1920; MBPS makes a small web file)
import AVFoundation

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1])
let asset = AVURLAsset(url: input)
let out = URL(fileURLWithPath: args[2])
let width = args.count > 4 ? Double(args[3])! : 1080, height = args.count > 4 ? Double(args[4])! : 1920

let track = try await asset.loadTracks(withMediaType: .video)[0]
let size = try await track.load(.naturalSize)
let duration = try await asset.load(.duration)
let base = max(width / size.width, height / size.height)

/// Scale `s` around a focus point given as a fraction of the source frame (y down), never exposing an edge.
func camera(_ s: Double, _ x: Double, _ y: Double) -> CGAffineTransform {
    let k = base * s, fx = x * size.width, fy = y * size.height
    let px = (width - size.width * base) / 2 + fx * base, py = (height - size.height * base) / 2 + fy * base
    let tx = min(0, max(width - size.width * k, px - fx * k)), ty = min(0, max(height - size.height * k, py - fy * k))
    return CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: tx, ty: ty)
}

let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
var keys: [(t: Double, m: CGAffineTransform)] = []
var trim = 0.0  // the demo marks where the first frame should be
let camURL = input.deletingPathExtension().appendingPathExtension("camera.json")
if let data = try? Data(contentsOf: camURL), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let frames = json["frames"] as? [[String: Double]] {
    trim = json["start"] as? Double ?? 0
    for f in frames.sorted(by: { $0["t", default: 0] < $1["t", default: 0] }) {
        let t = f["t", default: 0]
        if let last = keys.last, t <= last.t + 0.001 { continue }
        keys.append((t, camera(f["s", default: 1], f["x", default: 0.5], f["y", default: 0.5])))
    }
}
if keys.isEmpty { keys = [(0, camera(1, 0.5, 0.5))] }
layer.setTransform(keys[0].m, at: .zero)
for (a, b) in zip(keys, keys.dropFirst()) {
    layer.setTransformRamp(fromStart: a.m, toEnd: b.m, timeRange: CMTimeRange(start: CMTime(seconds: a.t, preferredTimescale: 600),
                                                                          end: CMTime(seconds: b.t, preferredTimescale: 600)))
}
layer.setTransform(keys[keys.count - 1].m, at: CMTime(seconds: keys[keys.count - 1].t, preferredTimescale: 600))

let instruction = AVMutableVideoCompositionInstruction()
instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
instruction.layerInstructions = [layer]
let composition = AVMutableVideoComposition()
composition.renderSize = CGSize(width: width, height: height)
composition.frameDuration = CMTime(value: 1, timescale: 60)
composition.instructions = [instruction]

let range = CMTimeRange(start: CMTime(seconds: trim, preferredTimescale: 600), end: duration)
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: out)
if args.count > 5, let mbps = Double(args[5]) {
    // Small file for the web: H.264 at a fixed bitrate, AAC audio.
    let reader = try AVAssetReader(asset: asset)
    let vOut = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    vOut.videoComposition = composition
    reader.add(vOut)
    reader.timeRange = range
    let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
    let aOut = audioTrack.map { AVAssetReaderTrackOutput(track: $0, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM]) }
    if let aOut { reader.add(aOut) }
    let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
    let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: mbps * 1_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                          AVVideoMaxKeyFrameIntervalKey: 120]])
    let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
                                                                     AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000])
    writer.add(vIn)
    if aOut != nil { writer.add(aIn) }
    writer.shouldOptimizeForNetworkUse = true
    reader.startReading()
    writer.startWriting()
    writer.startSession(atSourceTime: range.start)
    var videoDone = false, audioDone = aOut == nil
    while !(videoDone && audioDone) {
        var moved = false
        if !videoDone, vIn.isReadyForMoreMediaData {
            if let sample = vOut.copyNextSampleBuffer() { vIn.append(sample) } else { vIn.markAsFinished(); videoDone = true }
            moved = true
        }
        if !audioDone, let aOut, aIn.isReadyForMoreMediaData {
            if let sample = aOut.copyNextSampleBuffer() { aIn.append(sample) } else { aIn.markAsFinished(); audioDone = true }
            moved = true
        }
        if !moved { usleep(1000) }
    }
    await writer.finishWriting()
    guard writer.status == .completed else { fputs("error: \(writer.error?.localizedDescription ?? "export failed")\n", stderr); exit(1) }
} else {
    let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)!
    session.videoComposition = composition
    session.timeRange = range
    try await session.export(to: out, as: .mp4)
}
let bytes = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
print("Saved \(out.lastPathComponent): \(Int(width))×\(Int(height)), \(String(format: "%.1f", duration.seconds - trim)) s, \(bytes / 1_000_000) MB")
