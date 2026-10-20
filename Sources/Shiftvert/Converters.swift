import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

private let shrink = "arrow.down.right.and.arrow.up.left"

// MARK: Images (ImageIO)

enum Img {
    static let writable = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    static func actions(multi: Bool) -> [Action] {
        var list = [
            format("PNG", .png, "png", hide: ["png"]),
            format("JPG", .jpeg, "jpg", hide: ["jpg", "jpeg"]),
            format("HEIC", .heic, "heic", hide: ["heic"]),
        ]
        // Newer formats only when this Mac's ImageIO can write them.
        if let webp = UTType("org.webmproject.webp"), writable.contains(webp.identifier) {
            list.append(format("WebP", webp, "webp", hide: ["webp"]))
        }
        if let avif = UTType("public.avif"), writable.contains(avif.identifier) {
            list.append(format("AVIF", avif, "avif", hide: ["avif"]))
        }
        list += [
            format("TIFF", .tiff, "tiff", hide: ["tif", "tiff"]),
            format("GIF", .gif, "gif", hide: ["gif"]),
            format("BMP", .bmp, "bmp", hide: ["bmp"]),
            Action(title: "PDF", symbol: "doc.richtext", format: true, run: each { try PDF.fromImages([$0], name: nil) }),
            Action(title: "Compress", symbol: shrink, run: each(compress)),
            Action(title: "Resize 50%", symbol: "arrow.up.left.and.down.right.magnifyingglass", run: each(resize)),
            Action(title: "Crop", symbol: "crop", interactive: true, run: each(crop)),
            Action(title: "Strip EXIF", symbol: "location.slash", run: each(strip)),
        ]
        if multi { list.append(Action(title: "Merge PDF", symbol: "doc.on.doc") { [try PDF.fromImages(byName($0), name: "Images")] }) }
        return list
    }

    static func format(_ title: String, _ type: UTType, _ ext: String, hide: Set<String>) -> Action {
        Action(title: title, symbol: "photo", hideFor: hide, format: true, run: each { try convert($0, to: type, ext: ext) })
    }

    /// Real cameras top out around 100–200 MP. Anything bigger is refused, so a tiny crafted file
    /// (a "decompression bomb") can't make Shiftvert allocate gigabytes.
    static let maxPixels = 200_000_000

    static func source(_ url: URL, anySize: Bool = false) throws -> CGImageSource {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(s) > 0 else {
            throw Fail("Can't read \(url.lastPathComponent) as an image.")
        }
        let px = pixels(s)
        if !anySize && px > maxPixels {
            throw Fail("\(url.lastPathComponent) is too large to convert (\(px / 1_000_000) megapixels). Try Compress, which shrinks it first.")
        }
        return s
    }

    static func props(_ s: CGImageSource, at i: Int = 0) -> [CFString: Any] {
        CGImageSourceCopyPropertiesAtIndex(s, i, nil) as? [CFString: Any] ?? [:]
    }

    static func pixels(_ s: CGImageSource, at i: Int = 0) -> Int {
        let p = props(s, at: i), w = p[kCGImagePropertyPixelWidth] as? Int ?? 0, h = p[kCGImagePropertyPixelHeight] as? Int ?? 0
        return w.multipliedReportingOverflow(by: h).overflow ? .max : w * h
    }

    static func longSide(_ s: CGImageSource, at i: Int = 0) -> Int {
        let p = props(s, at: i)
        return max(p[kCGImagePropertyPixelWidth] as? Int ?? 0, p[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    /// Decoded image with the camera orientation applied, optionally scaled down.
    static func oriented(_ s: CGImageSource, at i: Int = 0, maxPixel: Int = .max) throws -> CGImage {
        let side = longSide(s, at: i)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(side, maxPixel)),
        ]
        guard side > 0, let img = CGImageSourceCreateThumbnailAtIndex(s, i, opts as CFDictionary) else {
            throw Fail("Can't decode this image.")
        }
        guard !blank(s, img) else { throw Fail("Can't decode this image. It may be damaged.") }
        return img
    }

    /// A truncated HEIC or AVIF "decodes" without any error, into an image that draws nothing or only black.
    static func blank(_ s: CGImageSource, _ img: CGImage) -> Bool {
        guard ["public.heic", "public.heif", "public.avif"].contains(CGImageSourceGetType(s) as String? ?? ""),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let p = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        ctx.setFillColor(red: 1, green: 0, blue: 1, alpha: 1)  // stays magenta where nothing gets drawn
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        return (0..<64).allSatisfy { i in p[i * 4 + 1] == 0 && p[i * 4] == p[i * 4 + 2] && [0, 255].contains(p[i * 4]) && p[i * 4 + 3] == 255 }
    }

    /// JPEG has no transparency, so paint transparent areas white instead of black.
    static func flatten(_ img: CGImage) -> CGImage {
        let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        func context(_ space: CGColorSpace?) -> CGContext? {
            space.flatMap { CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: $0, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) }
        }
        // The image's own RGB space keeps wide colour (Display P3); HDR and extended-range spaces need sRGB.
        let own = img.colorSpace.flatMap { $0.model == .rgb && !CGColorSpaceUsesITUR_2100TF($0) && !CGColorSpaceUsesExtendedRange($0) ? $0 : nil }
        guard let ctx = context(own) ?? context(CGColorSpace(name: CGColorSpace.sRGB)) else { return img }
        ctx.setFillColor(.white)
        ctx.fill(rect)
        ctx.draw(img, in: rect)
        return ctx.makeImage() ?? img
    }

    static func hasAlpha(_ s: CGImageSource) -> Bool { props(s)[kCGImagePropertyHasAlpha] as? Bool ?? false }

    /// True when some pixel is see-through; many images carry an alpha channel they never use.
    static func isTransparent(_ img: CGImage) -> Bool {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let a = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        return UnsafeBufferPointer(start: a, count: w * h).contains { $0 < 255 }
    }

    /// Keep the source format when ImageIO can write it, else fall back to PNG.
    static func sameFormat(_ s: CGImageSource, _ url: URL) -> (UTType, String) {
        // .heif (some Android phones) holds the same HEVC image ImageIO writes as HEIC.
        let id = CGImageSourceGetType(s) as String? == "public.heif" ? UTType.heic.identifier : CGImageSourceGetType(s) as String?
        if let id, writable.contains(id), let t = UTType(id) { return (t, url.pathExtension) }
        return (.png, "png")
    }

    /// Where animated GIF, PNG, HEICS and WebP files keep their frame time and loop count.
    static let anims: [(type: String, dict: CFString, delay: CFString, loop: CFString)] = [
        (UTType.gif.identifier, kCGImagePropertyGIFDictionary, kCGImagePropertyGIFDelayTime, kCGImagePropertyGIFLoopCount),
        (UTType.png.identifier, kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGDelayTime, kCGImagePropertyAPNGLoopCount),
        ("public.heics", kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSDelayTime, kCGImagePropertyHEICSLoopCount),
        ("org.webmproject.webp", kCGImagePropertyWebPDictionary, kCGImagePropertyWebPDelayTime, kCGImagePropertyWebPLoopCount),
    ]

    /// Frame time of an animated GIF, PNG, HEICS or WebP; nil for a still image.
    static func delay(_ s: CGImageSource, _ i: Int) -> Double? {
        let p = props(s, at: i)
        return anims.lazy.compactMap { (p[$0.dict] as? [CFString: Any])?[$0.delay] as? Double }.first.map { $0 > 0 ? $0 : 0.1 }
    }

    /// How many images to write as `type`: every frame of an animation or page of a TIFF when it can hold them, else
    /// the first. All of them together get the single-image size limit, since they're all held in memory until saved.
    static func frames(_ s: CGImageSource, _ url: URL, as type: UTType) throws -> Int {
        let n = CGImageSourceGetCount(s), animated = n > 1 && delay(s, 0) != nil
        let count = animated && anims.contains { $0.type == type.identifier }
            || type == .tiff && CGImageSourceGetType(s) as String? == type.identifier ? n : 1
        let total = (0..<count).reduce(0.0) { $0 + Double(pixels(s, at: $1)) }
        guard total <= Double(maxPixels) else {
            let images = count > 1 ? " in \(count) images" : ""
            throw Fail("\(url.lastPathComponent) is too large to convert (\(Int(total) / 1_000_000) megapixels\(images)).")
        }
        return count
    }

    static func destination(_ out: URL, _ type: UTType, count: Int = 1) throws -> CGImageDestination {
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, count, nil) else {
            throw Fail("Couldn't create \(out.lastPathComponent).")
        }
        return d
    }

    static func finalize(_ d: CGImageDestination, _ out: URL? = nil) throws {
        guard CGImageDestinationFinalize(d) else { throw Fail("Couldn't save the image.") }
        // ImageIO can report success after writing only a header (e.g. from a damaged HEIC), so read the result back.
        if let out, (CGImageSourceCreateWithURL(out as CFURL, nil).map { pixels($0) } ?? 0) == 0 { throw Fail("Couldn't save the image.") }
    }

    static func write(_ img: CGImage, to out: URL, type: UTType, quality: Double = 0.9) throws {
        let d = try destination(out, type)
        CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        try finalize(d, out)
    }

    /// Writes `n` images made by `frame`, with the animation timing, TIFF compression and `keep` properties but nothing
    /// else from the source. `gainMaps` keeps HDR photos HDR, for frames that are the source's own unchanged pixels.
    static func write(_ s: CGImageSource, _ n: Int, to out: URL, type: UTType, quality: Double = 0.9, keep: [CFString] = [],
                      gainMaps: Bool = false, frame: (Int) throws -> CGImage) throws {
        let images = try (0..<n).map(frame)
        let d = try destination(out, type, count: n)
        let anim = n > 1 ? anims.first { $0.type == type.identifier } : nil
        if let anim {
            let loop = ((CGImageSourceCopyProperties(s, nil) as? [CFString: Any])?[anim.dict] as? [CFString: Any])?[anim.loop] ?? 0
            CGImageDestinationSetProperties(d, [anim.dict: [anim.loop: loop]] as CFDictionary)
        }
        for (i, img) in images.enumerated() {
            let src = props(s, at: i)
            var p = src.filter { keep.contains($0.key) }
            p[kCGImageDestinationLossyCompressionQuality] = quality
            if let anim, let t = delay(s, i) { p[anim.dict] = [anim.delay: t] }
            if type == .tiff, let c = (src[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCompression] {
                p[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: c]
            }
            CGImageDestinationAddImage(d, img, p as CFDictionary)
            if gainMaps { addGainMaps(s, i, to: d) }
        }
        try finalize(d, out)
    }

    /// Copies image `i`'s HDR gain maps with only their HDR settings, not any other metadata stored with them.
    static func addGainMaps(_ s: CGImageSource, _ i: Int, to d: CGImageDestination) {
        var types = [kCGImageAuxiliaryDataTypeHDRGainMap]
        if #available(macOS 15, *) { types.append(kCGImageAuxiliaryDataTypeISOGainMap) }
        for t in types {
            guard var info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(s, i, t) as? [CFString: Any] else { continue }
            if let m = info[kCGImageAuxiliaryDataInfoMetadata].flatMap({ CGImageMetadataCreateMutableCopy($0 as! CGImageMetadata) }) {
                for tag in CGImageMetadataCopyTags(m) as? [CGImageMetadataTag] ?? [] {
                    let prefix = CGImageMetadataTagCopyPrefix(tag) as String? ?? "", name = CGImageMetadataTagCopyName(tag) as String? ?? ""
                    if !["HDRGainMap", "HDRToneMap"].contains(prefix) { CGImageMetadataRemoveTagWithPath(m, nil, "\(prefix):\(name)" as CFString) }
                }
                info[kCGImageAuxiliaryDataInfoMetadata] = m
            }
            CGImageDestinationAddAuxiliaryDataInfo(d, t, info as CFDictionary)
        }
    }

    static func convert(_ url: URL, to type: UTType, ext: String) throws -> URL {
        let s = try source(url)
        return try making(output(for: url, ext: ext)) { out in
            if type == .jpeg && hasAlpha(s) {
                try write(flatten(try oriented(s)), to: out, type: type)
            } else if type == .gif || type.identifier == "public.avif" {
                // Upright pixels and no metadata, since viewers ignore or misread these formats' orientation tags.
                try write(s, try frames(s, url, as: type), to: out, type: type) { try oriented(s, at: $0) }
            } else {
                // Re-encode straight from the source so metadata (date, orientation) carries over.
                let d = try destination(out, type)
                CGImageDestinationAddImageFromSource(d, s, 0, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
                try finalize(d, out)
            }
        }
    }

    static func compress(_ url: URL) throws -> URL {
        let s = try source(url, anySize: true)
        if CGImageSourceGetCount(s) > 1, delay(s, 0) != nil {
            throw Fail("Compress can't keep \(url.lastPathComponent)'s animation. Try Resize 50% instead.")
        }
        var img = try oriented(s, maxPixel: 3000)
        // HEIC keeps transparency, which JPEG would paint white.
        let heic = sameFormat(s, url).0 == .heic || hasAlpha(s) && isTransparent(img)
        if !heic && hasAlpha(s) { img = flatten(img) }
        return try smaller(try making(output(for: url, ext: heic ? "heic" : "jpg", suffix: " compressed")) {
            try write(img, to: $0, type: heic ? .heic : .jpeg, quality: 0.6)
        }, than: url)
    }

    static func resize(_ url: URL) throws -> URL {
        let s = try source(url)
        let (type, ext) = sameFormat(s, url)
        return try making(output(for: url, ext: ext, suffix: " 50%")) { out in
            try write(s, try frames(s, url, as: type), to: out, type: type) { i in
                try oriented(s, at: i, maxPixel: max(1, longSide(s, at: i) / 2))
            }
        }
    }

    /// Opens the crop editor; saves the chosen area at the chosen size, in the same format.
    static func crop(_ url: URL) async throws -> URL {
        let s = try source(url)
        let img = try oriented(s)
        guard let choice = await CropEditor.present(img, name: url.lastPathComponent) else { throw CancellationError() }
        guard var out = img.cropping(to: choice.rect) else { throw Fail("Couldn't crop the image.") }
        let w = Int(choice.size.width), h = Int(choice.size.height)
        if w != out.width || h != out.height {
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: out.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Fail("Couldn't resize the image.") }
            ctx.interpolationQuality = .high
            ctx.draw(out, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let scaled = ctx.makeImage() else { throw Fail("Couldn't resize the image.") }
            out = scaled
        }
        let (type, ext) = sameFormat(s, url)
        return try making(output(for: url, ext: ext, suffix: " cropped")) { try write(out, to: $0, type: type) }
    }

    /// Drops EXIF, GPS location, camera and other metadata, keeping orientation, resolution, animation and HDR. JPEG pixels
    /// are copied as they are when that comes out clean (no quality loss); everything else is re-encoded with nothing else carried over.
    static func strip(_ url: URL) throws -> URL {
        let s = try source(url, anySize: true)  // the JPEG copy decodes nothing; frames() limits the rest
        let (type, ext) = sameFormat(s, url)
        return try making(output(for: url, ext: ext, suffix: " clean")) { out in
            if type == .jpeg, let d = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) {
                let meta = CGImageMetadataCreateMutable()
                if let o = props(s)[kCGImagePropertyOrientation] as? Int, o != 1 {
                    CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, o as CFNumber)
                }
                let opts = [kCGImageDestinationMetadata: meta, kCGImageDestinationMergeMetadata: false] as CFDictionary
                if CGImageDestinationCopyImageSource(d, s, opts, nil), cleaned(out) { return }
                try? FileManager.default.removeItem(at: out)
            }
            // A GIF's orientation tag is ImageIO-only (browsers ignore it), so keep the pixels as browsers show them.
            let keep = type == .gif ? [] : [kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight]
            // Every size of an app icon, not just the largest.
            let n = type.identifier == "com.apple.icns" ? CGImageSourceGetCount(s) : try frames(s, url, as: type)
            try write(s, n, to: out, type: type, quality: 0.95, keep: keep, gainMaps: true) {
                guard let img = CGImageSourceCreateImageAtIndex(s, $0, nil), !blank(s, img) else {
                    throw Fail("Can't decode this image. It may be damaged.")
                }
                return img
            }
        }
    }

    /// ImageIO's lossless JPEG copy passes some blocks through untouched (a second Photoshop/IPTC segment, FlashPix or MPF
    /// data, images appended after the end such as previews with their own EXIF), so accept only what it writes itself.
    /// Its own Photoshop block still holds any thumbnail, EXIF/XMP copies and a checksum of the old IPTC, so it's cut out.
    static func cleaned(_ url: URL) -> Bool {
        guard var d = try? Data(contentsOf: url), let s = CGImageSourceCreateWithData(d as CFData, nil) else { return false }
        let tags = CGImageSourceCopyMetadataAtIndex(s, 0, nil).flatMap { CGImageMetadataCopyTags($0) as? [CGImageMetadataTag] } ?? []
        guard tags.allSatisfy({ ["Orientation", "hasXMP"].contains(CGImageMetadataTagCopyName($0) as String? ?? "") }) else { return false }
        var i = 2, seen: Set<String> = [], cut = false
        while i + 4 <= d.count, d[i] == 0xFF, d[i + 1] != 0xDA {  // the segments before the image data
            let end = min(i + 2 + (Int(d[i + 2]) << 8 | Int(d[i + 3])), d.count)
            if (0xE0...0xEF).contains(d[i + 1]) || d[i + 1] == 0xFE {
                let kind = ["JFIF", "Exif", "http://ns.adobe.com/xap/1.0/", "ICC_PROFILE", "Adobe", "AROT", "Photoshop 3.0"]
                    .first { d[(i + 4)...].starts(with: $0.utf8) }
                // A colour profile over 64 KB spans several numbered segments.
                guard let kind, seen.insert(kind == "ICC_PROFILE" ? "\(kind) \(d.dropFirst(i + 16).first ?? 0)" : kind).inserted
                else { return false }
                if kind == "Photoshop 3.0" { d.removeSubrange(i..<end); cut = true; continue }
            }
            i = end
        }
        guard d.range(of: Data([0xFF, 0xD9]), in: i..<d.count)?.upperBound == d.count else { return false }  // nothing after the image
        return !cut || (try? d.write(to: url)) != nil
    }
}

// MARK: Video & audio (AVFoundation, afconvert)

enum Media {
    static let videoActions = [
        Action(title: "MP4", symbol: "film", hideFor: ["mp4"], format: true, run: each { try await video($0, ext: "mp4", type: .mp4) }),
        Action(title: "MOV", symbol: "film", hideFor: ["mov"], format: true, run: each { try await video($0, ext: "mov", type: .mov) }),
        Action(title: "M4V", symbol: "film", hideFor: ["m4v"], format: true, run: each { try await video($0, ext: "m4v", type: .m4v) }),
        Action(title: "Compress", symbol: shrink, run: each {
            try smaller(try await export($0, preset: AVAssetExportPreset1280x720, ext: "mp4", type: .mp4, suffix: " compressed"), than: $0)
        }),
        Action(title: "GIF", symbol: "photo.stack", format: true, run: each(gif)),
        Action(title: "M4A", symbol: "music.note", format: true, run: each(extractAudio)),
        Action(title: "Trim", symbol: "scissors", interactive: true, run: each(trim)),
    ]

    static let audioActions = [
        afconvert("M4A", "m4a", hide: ["m4a"]) { _ in ["-f", "m4af", "-d", "aac@44100", "-b", "256000"] },
        afconvert("WAV", "wav", hide: ["wav"]) { ["-f", "WAVE", "-d", deep($0) ? "LEI24" : "LEI16"] },
        afconvert("AIFF", "aiff", hide: ["aif", "aiff"]) { ["-f", "AIFF", "-d", deep($0) ? "BEI24" : "BEI16"] },
        afconvert("FLAC", "flac", hide: ["flac"]) { _ in ["-f", "flac", "-d", "flac"] },
        // AAC needs more than 96 kbps for 5.1 and other multichannel audio.
        afconvert("Compress", "m4a", suffix: " compressed", symbol: shrink) { ["-f", "m4af", "-d", "aac@44100", "-b", String(48_000 * max(2, channels($0)))] },
        Action(title: "Trim", symbol: "scissors", interactive: true, run: each(trim)),
    ]

    static func afconvert(_ title: String, _ ext: String, suffix: String = "", symbol: String = "waveform", hide: Set<String> = [],
                          _ args: @escaping (URL) -> [String]) -> Action {
        Action(title: title, symbol: symbol, hideFor: hide, format: suffix.isEmpty, run: each { url in
            let out = try making(output(for: url, ext: ext, suffix: suffix)) { out in
                do { try runTool("/usr/bin/afconvert", args(url) + [url.path, out.path]) } catch { throw unreadable(url) }
            }
            return suffix.isEmpty ? out : try smaller(out, than: url)
        })
    }

    static func unreadable(_ url: URL) -> Fail {
        Fail("Couldn't convert \(url.lastPathComponent). It may be damaged or in a format macOS can't read.")
    }

    /// Shows a plain explanation instead of AVFoundation's own errors ("Operation Stopped", "Cannot Open").
    static func reading<T>(_ url: URL, _ work: () async throws -> T) async throws -> T {
        do { return try await work() } catch let error as Fail { throw error } catch is CancellationError { throw CancellationError() }
        catch { throw unreadable(url) }
    }

    static func format(_ url: URL) -> AudioStreamBasicDescription? {
        guard let f = (try? AVAudioFile(forReading: url))?.fileFormat else { return nil }
        return withExtendedLifetime(f) { f.streamDescription.pointee }  // the pointer lives only as long as f
    }

    /// Over 16 bits per sample, so lossless output keeps it (FLAC/ALAC flags: 1 = 16-bit, 2 = 20, 3 = 24, 4 = 32).
    static func deep(_ url: URL) -> Bool {
        guard let f = format(url) else { return false }
        return f.mBitsPerChannel > 16 || ([kAudioFormatFLAC, kAudioFormatAppleLossless].contains(f.mFormatID) && f.mFormatFlags >= 2)
    }

    static func channels(_ url: URL) -> Int { Int(format(url)?.mChannelsPerFrame ?? 2) }

    static func extractAudio(_ url: URL) async throws -> URL {
        guard try await !reading(url, { try await AVURLAsset(url: url).loadTracks(withMediaType: .audio) }).isEmpty else {
            throw Fail("\(url.lastPathComponent) has no sound.")
        }
        return try await export(url, preset: AVAssetExportPresetAppleM4A, ext: "m4a", type: .m4a)
    }

    static func export(_ url: URL, preset: String, ext: String, type: AVFileType, suffix: String = "",
                       range: CMTimeRange? = nil) async throws -> URL {
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: preset) else {
            throw Fail("\(url.lastPathComponent) can't be converted this way.")
        }
        if let range { session.timeRange = range }
        return try await making(output(for: url, ext: ext, suffix: suffix)) { out in
            try await reading(url) {
                if #available(macOS 15, *) {
                    try await session.export(to: out, as: type)
                } else {
                    guard session.supportedFileTypes.contains(type) else { throw Fail("\(url.lastPathComponent) can't be converted this way.") }
                    session.outputURL = out
                    session.outputFileType = type
                    await session.export()
                    if let error = session.error { throw error }
                }
            }
        }
    }

    /// Re-wraps without re-encoding when possible; HEVC becomes H.264 in MP4/M4V so it plays on Windows and Android.
    static func video(_ url: URL, ext: String, type: AVFileType, suffix: String = "", range: CMTimeRange? = nil) async throws -> URL {
        let hevc = [kCMVideoCodecType_HEVC, kCMVideoCodecType_DolbyVisionHEVC, kCMVideoCodecType_HEVCWithAlpha]
        let codec = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first?.load(.formatDescriptions).first
            .map(CMFormatDescriptionGetMediaSubType)
        if type == .mov || range != nil || !hevc.contains(where: { $0 == codec }) {
            do { return try await export(url, preset: AVAssetExportPresetPassthrough, ext: ext, type: type, suffix: suffix, range: range) } catch {}
        }
        return try await export(url, preset: AVAssetExportPresetHighestQuality, ext: ext, type: type, suffix: suffix, range: range)
    }

    static func trim(_ url: URL) async throws -> URL {
        let name = url.lastPathComponent
        let duration = try await reading(url) { try await AVURLAsset(url: url).load(.duration).seconds }
        guard duration.isFinite, duration > 0 else { throw Fail("Can't tell how long \(name) is.") }
        guard let (a, b) = try await MainActor.run(body: { try askRange(name: name, duration: duration) }) else { throw CancellationError() }
        let end = min(b, duration)
        guard a >= 0, a < duration, end > a else { throw Fail("Pick a start before the end, within \(clock(duration)).") }
        let range = CMTimeRange(start: CMTime(seconds: a, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        let ext = url.pathExtension.lowercased()
        if kind(of: url) == .audio {
            // Lossless and AAC files are cut without re-encoding; the rest (MP3, FLAC…) become AAC.
            let same: [String: AVFileType] = ["wav": .wav, "aif": .aiff, "aiff": .aiff, "m4a": .m4a, "caf": .caf]
            if let type = same[ext], let out = try? await export(url, preset: AVAssetExportPresetPassthrough, ext: ext, type: type,
                                                                 suffix: " trimmed", range: range) { return out }
            return try await export(url, preset: AVAssetExportPresetAppleM4A, ext: "m4a", type: .m4a, suffix: " trimmed", range: range)
        }
        let (outExt, type): (String, AVFileType) = ext == "mov" ? ("mov", .mov) : ext == "m4v" ? ("m4v", .m4v) : ("mp4", .mp4)
        return try await video(url, ext: outExt, type: type, suffix: " trimmed", range: range)
    }

    /// First 15 seconds at 10 fps, max 480 px.
    static func gif(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let track = try await reading(url, { try await asset.loadTracks(withMediaType: .video).first }) else {
            throw Fail("\(url.lastPathComponent) has no picture.")
        }
        let range = try await reading(url) { try await track.load(.timeRange) }
        // A damaged header can leave the length unknown (NaN).
        guard range.start.seconds.isFinite, range.duration.seconds.isFinite else { throw Fail("Couldn't read any frames from \(url.lastPathComponent).") }
        let fps = 10.0
        let count = max(1, Int(min(range.duration.seconds, 15) * fps))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)
        gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)
        let times = (0..<count).map { CMTimeAdd(range.start, CMTime(seconds: Double($0) / fps, preferredTimescale: 600)) }
        var frames: [CGImage] = []
        for await result in gen.images(for: times) {
            if case let .success(_, image, _) = result { frames.append(image) }
        }
        guard !frames.isEmpty else { throw Fail("Couldn't read any frames from \(url.lastPathComponent).") }
        return try making(output(for: url, ext: "gif")) { out in
            let d = try Img.destination(out, .gif, count: frames.count)
            CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
            for frame in frames { CGImageDestinationAddImage(d, frame, frameProps) }
            try Img.finalize(d, out)
        }
    }
}

// MARK: PDF (PDFKit)

enum PDF {
    static func actions(multi: Bool) -> [Action] {
        var list = [
            Action(title: "PNG", symbol: "photo", format: true, run: each { try toImages($0, .png, "png") }),
            Action(title: "JPG", symbol: "photo", format: true, run: each { try toImages($0, .jpeg, "jpg") }),
            Action(title: "TXT", symbol: "doc.plaintext", format: true, run: each(text)),
            Action(title: "Compress", symbol: shrink, run: each(compress)),
            Action(title: "Split", symbol: "square.split.1x2", run: each(split)),
        ]
        if multi { list.append(Action(title: "Merge", symbol: "doc.on.doc") { [try merge(byName($0))] }) }
        return list
    }

    static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw Fail("Can't open \(url.lastPathComponent).") }
        if doc.isLocked { throw Fail("\(url.lastPathComponent) is password-protected.") }
        return doc
    }

    static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width >= 1, box.height >= 1 else { return nil }
        let scale = min(2, 8000 / max(box.width, box.height))  // cap huge/malicious page sizes
        let turned = page.rotation % 180 != 0
        let w = Int((turned ? box.height : box.width) * scale), h = Int((turned ? box.width : box.height) * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: ctx)  // applies rotation and box origin itself
        return ctx.makeImage()
    }

    /// "name 01", "name 02"… so pages sort right everywhere, not only in Finder.
    static func pageName(_ base: String, _ i: Int, of count: Int) -> String {
        "\(base) \(String(format: "%0\(String(count).count)d", i + 1))"
    }

    /// One image for a single page; a folder of images for longer PDFs.
    static func toImages(_ url: URL, _ type: UTType, _ ext: String) throws -> URL {
        let doc = try open(url)
        let base = fit(url.deletingPathExtension().lastPathComponent, " 9999." + ext)
        func image(_ i: Int) throws -> CGImage {
            guard let page = doc.page(at: i), let img = render(page) else { throw Fail("Can't render page \(i + 1) of \(url.lastPathComponent).") }
            return img
        }
        if doc.pageCount == 1 {
            let img = try image(0)
            return try making(output(for: url, ext: ext)) { try Img.write(img, to: $0, type: type) }
        }
        return try making(output(for: url, ext: "", suffix: " pages")) { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
            for i in 0..<doc.pageCount {
                try autoreleasepool {
                    try Img.write(try image(i), to: dir.appendingPathComponent(pageName(base, i, of: doc.pageCount)).appendingPathExtension(ext), type: type)
                }
            }
        }
    }

    static func text(_ url: URL) throws -> URL {
        guard let string = try open(url).string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Fail("No text found in \(url.lastPathComponent) (it may be a scan).")
        }
        // Final letters (ךםןףץ) only end words; if they mostly start words, the Hebrew came out reversed.
        let finals = Set("ךםןףץ"), words = string.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }.filter { $0.count > 1 }
        let hebrew = string.unicodeScalars.contains { (0x05D0...0x05EA).contains($0.value) }
        if hebrew, words.filter({ finals.contains($0.first!) }).count >= words.filter({ finals.contains($0.last!) }).count {
            throw Fail("The Hebrew text in \(url.lastPathComponent) can't be pulled out in the right order.")
        }
        return try making(output(for: url, ext: "txt")) { try string.write(to: $0, atomically: true, encoding: .utf8) }
    }

    static func compress(_ url: URL) throws -> URL {
        let doc = try open(url)
        guard doc.allowsDocumentAssembly else { throw Fail("\(url.lastPathComponent) is protected against changes, so it can't be compressed.") }
        // PDFKit copies an untouched file as is, so mark it changed; JPEG only when no image has a mask (it discolours them).
        if let first = doc.page(at: 0) { doc.removePage(at: 0); doc.insert(first, at: 0) }
        let data = try? Data(contentsOf: url, options: .alwaysMapped)
        let masked = data.map { d in ["/SMask", "/Mask"].contains { d.range(of: Data($0.utf8)) != nil } } ?? true
        let opts: [PDFDocumentWriteOption: Any] = [.optimizeImagesForScreenOption: true, .saveImagesAsJPEGOption: !masked]
        return try smaller(try making(output(for: url, ext: "pdf", suffix: " compressed")) { out in
            guard doc.write(to: out, withOptions: opts) else {
                throw Fail("Couldn't save the PDF.")
            }
        }, than: url)
    }

    static func split(_ url: URL) throws -> URL {
        let doc = try open(url)
        guard doc.pageCount > 1 else { throw Fail("\(url.lastPathComponent) has only one page.") }
        let base = fit(url.deletingPathExtension().lastPathComponent, " 9999.pdf")
        return try making(output(for: url, ext: "", suffix: " split")) { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
                let single = PDFDocument()
                single.insert(page, at: 0)
                let file = dir.appendingPathComponent(pageName(base, i, of: doc.pageCount)).appendingPathExtension("pdf")
                guard single.write(to: file) else { throw Fail("Couldn't save page \(i + 1).") }
            }
        }
    }

    static func merge(_ urls: [URL]) throws -> URL {
        let merged = PDFDocument()
        for url in urls {
            let doc = try open(url)
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i)?.copy() as? PDFPage { merged.insert(page, at: merged.pageCount) }
            }
        }
        return try making(unique(in: urls[0].deletingLastPathComponent(), base: "Merged", ext: "pdf")) {
            guard merged.write(to: $0) else { throw Fail("Couldn't save the PDF.") }
        }
    }

    /// A4, or US Letter where that's the Mac's default paper (US, Canada, Mexico…).
    static let paper = NSPrintInfo().paperSize.width == 612 ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)

    /// Images become pages fitted onto the paper, turned to match; every page of a multi-page TIFF is kept.
    static func fromImages(_ urls: [URL], name: String?) throws -> URL {
        let doc = PDFDocument()
        for url in urls {
            let s = try Img.source(url)
            let pages = CGImageSourceGetType(s) as String? == UTType.tiff.identifier ? CGImageSourceGetCount(s) : 1
            for i in 0..<pages {
                try autoreleasepool {
                    // 3508 px is A4 at 300 dpi: full print quality without decoding a 48 MP photo at full size.
                    let cg = i == 0 ? try Img.oriented(s, maxPixel: 3508) : try tiffPage(s, i, of: url)
                    let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    let landscape = cg.width > cg.height
                    let box = CGRect(origin: .zero, size: landscape ? CGSize(width: paper.height, height: paper.width) : paper)
                    guard let page = PDFPage(image: img, options: [.mediaBox: box, .compressionQuality: 0.85]) else {
                        throw Fail("Can't add \(url.lastPathComponent) to the PDF.")
                    }
                    doc.insert(page, at: doc.pageCount)
                }
            }
        }
        let out = name.map { unique(in: urls[0].deletingLastPathComponent(), base: $0, ext: "pdf") } ?? output(for: urls[0], ext: "pdf")
        return try making(out) { guard doc.write(to: $0) else { throw Fail("Couldn't save the PDF.") } }
    }

    /// Page `i` of a TIFF, upright and at most 3508 px, with the same size limit as the first page.
    static func tiffPage(_ s: CGImageSource, _ i: Int, of url: URL) throws -> CGImage {
        let p = CGImageSourceCopyPropertiesAtIndex(s, i, nil) as? [CFString: Any] ?? [:]
        let w = p[kCGImagePropertyPixelWidth] as? Int ?? 0, h = p[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(max(w, h), 3508)),
        ]
        guard w > 0, h > 0, w * h <= Img.maxPixels, let img = CGImageSourceCreateThumbnailAtIndex(s, i, opts as CFDictionary) else {
            throw Fail("Can't read page \(i + 1) of \(url.lastPathComponent).")
        }
        return img
    }
}

// MARK: Documents (textutil, AppKit text system)

enum Doc {
    static let actions = [
        Action(title: "PDF", symbol: "doc.richtext", format: true, run: each { url in
            try check(url, pictures: true)
            nonisolated(unsafe) let text = try load(url)  // only handed over to the main thread
            // Layout and printing run on the main thread, so a huge text would freeze Shiftvert for a long time.
            let rtl = text.string.unicodeScalars.contains { (0x0590...0x08FF).contains($0.value) }  // lays out about 7× slower
            guard text.length < (rtl ? 400_000 : 2_000_000) else { throw Fail("\(url.lastPathComponent) is too long to turn into a PDF.") }
            return try await MainActor.run { try pdf(text, for: url) }
        }),
        textutil("DOCX", "docx", hide: ["docx"]),
        textutil("RTF", "rtf", hide: ["rtf"]),
        textutil("TXT", "txt", hide: ["txt"]),
        textutil("HTML", "html", hide: ["html", "htm"]),
        textutil("ODT", "odt", hide: ["odt"]),
    ]

    static func isPlain(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension).map { $0.conforms(to: .plainText) && !$0.conforms(to: .html) } ?? false
    }

    /// Told their type, Apple's readers reject a fake or damaged Word/ODT file instead of turning it into pages of junk.
    static let zipped: [String: NSAttributedString.DocumentType] = ["docx": .officeOpenXML, "odt": .openDocument]
    static let typed = zipped.merging(["doc": .docFormat]) { a, _ in a }

    static func check(_ url: URL, pictures: Bool) throws {
        let ext = url.pathExtension.lowercased()
        guard zipped[ext] != nil else { return }
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.prefix(2) == Data("PK".utf8) else {
            throw Fail("\(url.lastPathComponent) can't be read. It may be password-protected or damaged.")
        }
        // Apple's Word/ODT reader leaves pictures out, so say so instead of quietly dropping them.
        if pictures, data.range(of: Data((ext == "docx" ? "word/media/" : "Pictures/").utf8)) != nil {
            throw Fail("\(url.lastPathComponent) has pictures, which macOS's built-in converter would leave out. Convert it with the app that made it instead.")
        }
    }

    /// Old Windows text files aren't UTF-8; without this they're read as Mac Roman ("CafÈ").
    static func encoding(_ url: URL) -> UInt? {
        guard isPlain(url), let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        let raw = NSString.stringEncoding(for: data, encodingOptions: [.suggestedEncodingsKey: [String.Encoding.utf8.rawValue], .allowLossyKey: false],
                                          convertedString: nil, usedLossyConversion: nil)
        let unicode: [String.Encoding] = [.utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian, .utf32LittleEndian]
        if unicode.contains(where: { $0.rawValue == raw }) { return raw }
        // NSString can't tell Windows Hebrew from Western. Its letters and points are C0–FA; accented Latin never has 3 in a row.
        let hebrew = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsHebrew.rawValue)))
        var run = 0
        let guesses: [String.Encoding] = data.contains { run = (0xC0...0xFA).contains($0) ? run + 1 : 0; return run == 3 }
            ? [hebrew, .windowsCP1252] : [.windowsCP1252]
        return guesses.first { String(data: data, encoding: $0) != nil }?.rawValue ?? (raw == 0 ? nil : raw)
    }

    static func textutil(_ title: String, _ format: String, hide: Set<String>) -> Action {
        Action(title: title, symbol: "doc.text", hideFor: hide, format: true, run: each { url in
            try check(url, pictures: format != "txt")
            let ext = url.pathExtension.lowercased()
            // Markdown, code etc. aren't recognised by extension, so tell textutil they're plain text.
            var input = isPlain(url) ? ["-format", "txt"] : typed[ext] != nil ? ["-format", ext] : []
            if let e = encoding(url), let name = CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(e)) {
                input += ["-inputencoding", name as String]
            }
            return try making(output(for: url, ext: format)) { out in
                do { try runTool("/usr/bin/textutil", input + ["-noload", "-nostore", "-convert", format, "-output", out.path, url.path]) }
                catch { throw Fail("Can't read \(url.lastPathComponent) as a document.") }
                // textutil quietly writes nothing for a file that isn't really in its format.
                guard FileManager.default.fileExists(atPath: out.path) else { throw Fail("Can't read \(url.lastPathComponent) as a document.") }
            }
        })
    }

    /// Reads a document as styled text, off the main thread. Web pages go through textutil -noload first so
    /// opening them can never make network requests.
    static func load(_ url: URL) throws -> NSAttributedString {
        var opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        if isPlain(url) {
            opts[.documentType] = NSAttributedString.DocumentType.plain
        } else if let t = typed[url.pathExtension.lowercased()] {
            opts[.documentType] = t
        }
        if let e = encoding(url) { opts[.characterEncoding] = e }
        var source = url
        if let t = UTType(filenameExtension: url.pathExtension), t.conforms(to: .html) || t.conforms(to: .webArchive) {
            source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".rtfd")
            try runTool("/usr/bin/textutil", ["-noload", "-convert", "rtfd", "-output", source.path, url.path])
        }
        defer { if source != url { try? FileManager.default.removeItem(at: source) } }
        do {
            return try NSAttributedString(url: source, options: opts, documentAttributes: nil)
        } catch {
            throw Fail("Can't read \(url.lastPathComponent) as a document.")
        }
    }

    /// Lays the text out on A4 or Letter pages (see PDF.paper) and "prints" it to a PDF file.
    @MainActor static func pdf(_ text: NSAttributedString, for url: URL) throws -> URL {
        return try making(output(for: url, ext: "pdf")) { out in
            let info = NSPrintInfo()
            info.paperSize = PDF.paper
            (info.topMargin, info.bottomMargin, info.leftMargin, info.rightMargin) = (54, 54, 54, 54)
            info.horizontalPagination = .fit
            info.isVerticallyCentered = false
            info.verticalPagination = .automatic
            info.jobDisposition = .save
            info.dictionary().setObject(out, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString)

            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: PDF.paper.width - 108, height: 1))
            view.appearance = NSAppearance(named: .aqua)  // black text on white even in Dark Mode
            view.isVerticallyResizable = true
            view.isHorizontallyResizable = false
            view.textContainer?.widthTracksTextView = true
            view.textStorage?.setAttributedString(text)
            if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
            view.sizeToFit()

            let op = NSPrintOperation(view: view, printInfo: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            guard op.run(), FileManager.default.fileExists(atPath: out.path) else { throw Fail("Couldn't create the PDF.") }
        }
    }
}
