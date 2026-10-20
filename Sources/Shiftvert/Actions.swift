import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Fail: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct Action {
    let title: String
    let symbol: String
    /// Extensions for which this action is pointless (e.g. "PNG" on a .png).
    var hideFor: Set<String> = []
    /// A target file format; the ring shows its name in bold instead of an icon.
    var format = false
    /// Opens its own window first (crop editor, trim times), so no "working" toast until it's done.
    var interactive = false
    let run: ([URL]) async throws -> [URL]
}

enum Kind { case image, video, audio, pdf, document, other }

private let documentTypes = [
    "org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc", "org.oasis-open.opendocument.text",
    "com.apple.webarchive", "public.rtf", "public.html",
].compactMap(UTType.init)

private let readableImages = Set(CGImageSourceCopyTypeIdentifiers() as? [String] ?? [])
/// Audio/video types AVFoundation can actually open (WebM, WMV, FLV, WMA… are not, so they only get Zip).
private let playable = Set(AVURLAsset.audiovisualTypes().map(\.rawValue))

func kind(of url: URL) -> Kind {
    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return .other }
    guard let t = UTType(filenameExtension: url.pathExtension) else { return .other }
    // Photos with odd extensions (.jfif from browsers, .jpg_large from X) still open in ImageIO.
    if t.isDynamic {
        guard onDisk(url) == true, let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return .other }
        return (CGImageSourceGetType(src) as String?).map(readableImages.contains) == true ? .image : .other
    }
    if t.conforms(to: .pdf) { return .pdf }
    if t.conforms(to: .image) { return readableImages.contains(t.identifier) ? .image : .other }
    if let ts = UTType("public.mpeg-2-transport-stream"), t.conforms(to: ts), !isTransportStream(url) { return .other }
    if t.conforms(to: .audio) { return playable.contains(t.identifier) ? .audio : .other }
    if t.conforms(to: .audiovisualContent) { return playable.contains(t.identifier) ? .video : .other }
    if t.conforms(to: .plainText) || documentTypes.contains(where: t.conforms(to:)) { return .document }
    return .other
}

/// .ts and .mts are also TypeScript files: only a real transport stream (sync byte 0x47 every 188 bytes,
/// after a 4-byte timecode in camcorder .mts/.m2ts) counts as video.
private func isTransportStream(_ url: URL) -> Bool {
    guard let local = onDisk(url) else { return false }
    if !local { return true }  // an iCloud placeholder keeps the extension's verdict instead of downloading here
    guard let h = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? h.close() }
    guard let d = try? h.read(upToCount: 197), d.count == 197 else { return false }
    return d[0] == 0x47 && d[188] == 0x47 || d[4] == 0x47 && d[196] == 0x47
}

/// The wheel is built on the main thread, so only regular files whose data is on this Mac get peeked into: opening a
/// pipe blocks forever and reading an iCloud placeholder downloads it first. nil when it isn't a regular file.
private func onDisk(_ url: URL) -> Bool? {
    var s = stat()
    guard stat(url.path, &s) == 0, s.st_mode & S_IFMT == S_IFREG else { return nil }
    return s.st_flags & UInt32(SF_DATALESS) == 0
}

func actions(for urls: [URL]) -> [Action] {
    guard !urls.isEmpty else { return [] }
    let kinds = Set(urls.map(kind(of:)))
    let multi = urls.count > 1
    var list: [Action] = []
    if kinds.count == 1 {
        switch kinds.first! {
        case .image: list = Img.actions(multi: multi)
        case .video: list = Media.videoActions
        case .audio: list = Media.audioActions
        case .pdf: list = PDF.actions(multi: multi)
        case .document: list = Doc.actions
        case .other: break
        }
    }
    let exts = Set(urls.map { $0.pathExtension.lowercased() })
    list.removeAll { !$0.hideFor.isEmpty && exts.isSubset(of: $0.hideFor) }
    // In a mixed selection, files already in the target format are left alone instead of re-encoded into "name 2" copies.
    list = list.map { a in
        a.hideFor.isDisjoint(with: exts) ? a : Action(title: a.title, symbol: a.symbol, hideFor: a.hideFor, format: a.format, interactive: a.interactive) {
            try await a.run($0.filter { !a.hideFor.contains($0.pathExtension.lowercased()) })
        }
    }
    list.append(Action(title: "Zip", symbol: "doc.zipper") { try zip($0) })
    return list
}

// MARK: Helpers

/// Some files converted and some didn't; carries both so the toast and alert can say exactly what happened.
struct PartialFailure: LocalizedError {
    let outs: [URL]
    let failures: [(name: String, reason: String)]
    var errorDescription: String? { "\(outs.count) saved, \(failures.count) couldn't be converted" }
    var recoverySuggestion: String? {
        failures.prefix(6).map { "• \($0.name): \($0.reason)" }.joined(separator: "\n") + (failures.count > 6 ? "\n…" : "")
    }
}

/// Runs a per-file conversion over every dropped file. One bad file doesn't stop the rest.
func each(_ convert: @escaping (URL) async throws -> URL) -> ([URL]) async throws -> [URL] {
    { urls in
        var outs: [URL] = [], failures: [(name: String, reason: String)] = []
        for url in urls {
            do {
                outs.append(try await convert(url))
            } catch is CancellationError {
                // Cancel in Crop or Trim stops the batch, but files already saved are still reported.
                if outs.isEmpty { throw CancellationError() }
                break
            } catch {
                if urls.count == 1 { throw error }
                failures.append((url.lastPathComponent, error.localizedDescription))
            }
        }
        if outs.isEmpty, let first = failures.first { throw Fail("None of the \(urls.count) files could be converted. \(first.reason)") }
        if !failures.isEmpty { throw PartialFailure(outs: outs, failures: failures) }
        return outs
    }
}

/// A path in `dir` that doesn't exist yet: "name.ext", "name 2.ext", … (ext "" makes a folder name).
func unique(in dir: URL, base: String, ext: String) -> URL {
    let dir = visible(dir), base = fit(base, "." + ext)
    func make(_ b: String) -> URL {
        ext.isEmpty ? dir.appendingPathComponent(b, isDirectory: true) : dir.appendingPathComponent(b).appendingPathExtension(ext)
    }
    var url = make(base), n = 2
    // attributesOfItem doesn't follow symlinks, so a planted dangling link can't redirect the write elsewhere.
    while Running.shared.claimed(url) || (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil { url = make("\(base) \(n)"); n += 1 }
    return url
}

/// Output next to the source, never overwriting anything.
func output(for src: URL, ext: String, suffix: String = "") -> URL {
    unique(in: src.deletingLastPathComponent(), base: fit(src.deletingPathExtension().lastPathComponent, suffix + "." + ext) + suffix, ext: ext)
}

/// Shortens a very long name so "name 99<tail>" stays under the 255-byte limit, with room for ImageIO's longer temporary name.
func fit(_ name: String, _ tail: String) -> String {
    var name = name
    while name.count > 1, (name + " 99" + tail).utf8.count > 235 { name.removeLast() }
    return name
}

/// Files dragged out of hidden temporary or app folders (screenshot thumbnails, mail and chat attachments)
/// get their results in Downloads, where people can find them.
private func visible(_ dir: URL) -> URL {
    let p = dir.path, lib = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/"
    let hidden = p.contains("/TemporaryItems/") || p.hasPrefix(lib) && !p.hasPrefix(lib + "Mobile Documents/") && !p.hasPrefix(lib + "CloudStorage/")
    return hidden ? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] : dir
}

/// Runs `work` to produce `out`. It writes into a scratch folder that quitting deletes, and the result only moves into
/// place once complete, so a half-written file never sits next to the original. Also catches tools that report
/// success without writing anything, and folders that can't be written to.
func making(_ out: URL, _ work: (URL) throws -> Void) throws -> URL {
    let item = try scratch(for: out)
    defer { discard(item, out) }
    do { try work(item) } catch { throw roomy(error, out) }
    return try place(item, at: out)
}

func making(_ out: URL, _ work: (URL) async throws -> Void) async throws -> URL {
    let item = try scratch(for: out)
    defer { discard(item, out) }
    do { try await work(item) } catch { throw roomy(error, out) }
    return try place(item, at: out)
}

/// A full drive makes tools fail with raw messages that name the scratch folder.
private func roomy(_ error: Error, _ out: URL) -> Error {
    guard !(error is CancellationError) else { return error }
    let free = try? out.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
    return (free ?? .max) < 5_000_000 ? Fail("There isn't enough free space on this drive to save \(out.lastPathComponent).") : error
}

private func scratch(for out: URL) throws -> URL {
    let fm = FileManager.default, dir = out.deletingLastPathComponent()
    guard fm.isWritableFile(atPath: dir.path) else { throw cantSave(into: dir) }
    // Same drive as the result, so the final move is instant.
    let tmp = (try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: dir, create: true))
        ?? dir.appendingPathComponent(".Shiftvert-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    Running.shared.add(tmp)
    Running.shared.claim(out)
    // A crash or Force Quit leaves its scratch folder behind, and on other drives nothing else ever removes it.
    let day = Date().addingTimeInterval(-86_400)
    for old in (try? fm.contentsOfDirectory(at: tmp.deletingLastPathComponent(), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    where old.lastPathComponent.hasPrefix("NSIRD_Shiftvert_")
        && ((try? old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()) < day {
        try? fm.removeItem(at: old)
    }
    return tmp.appendingPathComponent(out.lastPathComponent, isDirectory: out.hasDirectoryPath)
}

private func discard(_ item: URL, _ out: URL) {
    let tmp = item.deletingLastPathComponent()
    Running.shared.release(out)
    removeScratch(tmp)
    Running.shared.remove(tmp)
}

/// On other drives scratch folders sit in a ".TemporaryItems" folder at the top, which would otherwise stay once empty.
private func removeScratch(_ tmp: URL) {
    try? FileManager.default.removeItem(at: tmp)
    guard tmp.path.contains("/.TemporaryItems/") else { return }
    var p = tmp.deletingLastPathComponent()
    for _ in 0..<3 { guard rmdir(p.path) == 0 else { return }; p = p.deletingLastPathComponent() }
}

/// Read-only folders, and folders macOS hasn't allowed Shiftvert into (it may only refuse at the final move).
func cantSave(into dir: URL) -> Fail {
    Fail("Can't save into “\(dir.lastPathComponent)”. Check that the folder isn't read-only and that Shiftvert is allowed in System Settings → Privacy & Security → Files & Folders.")
}

private let placing = NSLock()

/// Moves the finished result to `out`, or the next free name if another job got there first. Never replaces anything.
private func place(_ item: URL, at out: URL) throws -> URL {
    guard (try? item.checkResourceIsReachable()) == true else { throw Fail("Couldn't create \(out.lastPathComponent).") }
    return try placing.withLock {
        var out = out
        let dir = out.deletingLastPathComponent()
        while renamex_np(item.path, out.path, UInt32(RENAME_EXCL)) != 0 {
            if errno != EEXIST {
                // Drives that can't rename exclusively (exFAT, some shares): moveItem refuses to replace, and the lock
                // keeps other jobs from slipping in between its check and the move.
                do { try FileManager.default.moveItem(at: item, to: out); return out }
                catch CocoaError.fileWriteFileExists {}
                catch CocoaError.fileWriteNoPermission, CocoaError.fileWriteVolumeReadOnly { throw cantSave(into: dir) }
            }
            out = out.hasDirectoryPath ? unique(in: dir, base: out.lastPathComponent, ext: "")
                : unique(in: dir, base: out.deletingPathExtension().lastPathComponent, ext: out.pathExtension)
        }
        return out
    }
}

/// Helper processes and scratch folders (including half-written results) in use, so quitting Shiftvert can stop and clean them up.
final class Running: @unchecked Sendable {
    static let shared = Running()
    private let lock = NSLock()
    private var tools: [ObjectIdentifier: Process] = [:]
    private var folders: Set<URL> = []
    private var names: Set<String> = []

    func add(_ p: Process) { lock.withLock { tools[ObjectIdentifier(p)] = p } }
    func remove(_ p: Process) { lock.withLock { _ = tools.removeValue(forKey: ObjectIdentifier(p)) } }
    func add(_ folder: URL) { lock.withLock { _ = folders.insert(folder) } }
    func remove(_ folder: URL) { lock.withLock { _ = folders.remove(folder) } }
    /// Results still being written: unique() skips their names, so a job started meanwhile picks another.
    func claim(_ out: URL) { lock.withLock { _ = names.insert(out.path) } }
    func release(_ out: URL) { lock.withLock { _ = names.remove(out.path) } }
    func claimed(_ out: URL) -> Bool { lock.withLock { names.contains(out.path) } }

    func stopAll() {
        let (ps, fs) = lock.withLock { (Array(tools.values), folders) }
        ps.forEach { $0.terminate() }
        fs.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

/// Runs a built-in macOS tool directly (no shell), so file names can't be interpreted as commands.
func runTool(_ path: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let err = Pipe()
    p.standardError = err
    p.standardOutput = FileHandle.nullDevice
    try p.run()
    Running.shared.add(p)
    defer { Running.shared.remove(p) }
    let data = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        throw Fail("\(URL(fileURLWithPath: path).lastPathComponent) failed: \(String(decoding: data, as: UTF8.self).prefix(300))")
    }
}

/// Keeps a compressed result only if it saved at least 5%.
func smaller(_ out: URL, than src: URL) throws -> URL {
    let size = { (u: URL) in (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    guard size(out) < size(src) * 95 / 100 else {
        try? FileManager.default.removeItem(at: out)
        throw Fail("\(src.lastPathComponent) is already as small as it gets.")
    }
    return out
}

/// ditto flags that keep Finder metadata out of the archive: no "downloaded from" URLs, quarantine flags,
/// ACLs or AppleDouble "._" / __MACOSX files.
private let plainZip = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl"]

/// ditto waits forever on a named pipe or socket, so those are refused up front.
private func pipeOrSocket(in url: URL) -> URL? {
    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
    func special(_ u: URL) -> Bool {
        guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return false }
        return v.isRegularFile == false && v.isDirectory == false && v.isSymbolicLink == false
    }
    if special(url) { return url }
    guard let all = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return nil }
    for case let u as URL in all where special(u) { return u }
    return nil
}

func zip(_ urls: [URL]) throws -> [URL] {
    let fm = FileManager.default
    let isDir = { (u: URL) in (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    if let bad = urls.lazy.compactMap(pipeOrSocket).first { throw Fail("“\(bad.lastPathComponent)” is a pipe or socket, which can't be zipped.") }
    // exFAT/FAT drives keep extended attributes in hidden "._" files that ditto would archive, so folders there are staged.
    func fat(_ u: URL) -> Bool {
        var s = statfs()
        guard statfs(u.path, &s) == 0 else { return false }
        return ["exfat", "msdos"].contains(withUnsafeBytes(of: s.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) })
    }
    if urls.count == 1, !(isDir(urls[0]) && fat(urls[0])) {
        let src = urls[0].resolvingSymlinksInPath()  // a link to a folder zips as that folder
        let out = unique(in: urls[0].deletingLastPathComponent(), base: urls[0].lastPathComponent, ext: "zip")
        // Only a folder keeps its own name inside the archive; a single file sits at the root, like Finder's Compress.
        let keep = isDir(src) ? ["--keepParent"] : []
        return [try making(out) { try ditto(plainZip + keep + [src.path, $0.path], urls[0].lastPathComponent) }]
    }
    // Stage the items on the same volume (hard links or APFS clones: instant, no extra space) so the archive
    // has every item at its root.
    let dest = urls[0].deletingLastPathComponent()
    let stage = (try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: dest, create: true))
        ?? fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: stage, withIntermediateDirectories: true)
    Running.shared.add(stage)
    defer { removeScratch(stage); Running.shared.remove(stage) }
    for url in urls {
        // Same-named files from different folders get "name 2", "name 3"… instead of failing.
        let ext = url.pathExtension, base = isDir(url) || ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var item = stage.appendingPathComponent(url.lastPathComponent), n = 2
        while (try? fm.attributesOfItem(atPath: item.path)) != nil {
            item = stage.appendingPathComponent(isDir(url) || ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        // A folder that can't be hard-linked (exFAT, FAT) leaves a partial copy behind, so clear it before copying.
        do { try fm.linkItem(at: url, to: item) } catch { try? fm.removeItem(at: item); try fm.copyItem(at: url, to: item) }
    }
    // Copies on drives without native extended attributes (exFAT, FAT) get AppleDouble "._" files, which Foundation
    // doesn't list but ditto would archive; delete each item's "._" companion from the stage.
    if let all = fm.enumerator(at: stage, includingPropertiesForKeys: nil) {
        for case let u as URL in all {
            let name = u.lastPathComponent
            unlink(name.hasPrefix("._") ? u.path : u.deletingLastPathComponent().appendingPathComponent("._" + name).path)
        }
    }
    let out = unique(in: dest, base: urls.count == 1 ? urls[0].lastPathComponent : "Archive", ext: "zip")
    return [try making(out) { try ditto(plainZip + [stage.path, $0.path], out.lastPathComponent) }]
}

/// ditto's own errors name scratch paths and Unix codes, so say it plainly.
private func ditto(_ args: [String], _ name: String) throws {
    do { try runTool("/usr/bin/ditto", args) } catch {
        throw Fail("Couldn't zip \(name). Something inside it can't be opened, such as a locked file or one that belongs to another user.")
    }
}

func byName(_ urls: [URL]) -> [URL] {
    urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}
