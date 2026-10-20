// Only in `./build.sh demo` builds, so the app people download doesn't include a screen recorder.
#if SHIFTVERT_DEMO
import AppKit
import AVFoundation
import ImageIO
import PDFKit
import QuickLookThumbnailing
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Product video: `Shiftvert --demo OUT.mov [--wide]` plays a scripted, beat-synced demo of the real wheel (fake
/// Finder window and pointer, real conversions, original music and sound effects) and records only Shiftvert's own
/// windows with ScreenCaptureKit. Camera moves are written to OUT.camera.json for scripts/export-video.swift.
@available(macOS 15, *)
@MainActor final class Demo {
    private unowned let app: AppDelegate
    private let output: URL
    private let wide: Bool
    private let frame: NSRect
    private let stage: NSWindow
    private let overlay: NSWindow
    private let root = NSView()
    private let typeView = NSView()
    private let finder = FinderWindow()
    private let cursor = NSImageView()
    private let carried = NSImageView()
    private let shiftKey = KeyCap(glyph: "⇧", word: "shift")
    private let optionKey = KeyCap(glyph: "⌥", word: "option")
    private let keys = NSStackView()
    private let sound = DemoSound()
    private let recorder = DemoRecorder()
    private var caption: CATextLayer?
    private var point = NSPoint.zero        // fake pointer, stage coordinates
    private var lastHover: Int?
    private var held: [URL] = []
    private var t0 = CACurrentMediaTime()   // beat clock
    private var trimStart = 0.0
    private let badgeView = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    private var badge: CALayer { badgeView.layer! }
    private var recStart = CACurrentMediaTime()
    private var camera: [[String: Double]] = []
    private var zoom = (s: 1.0, x: 0.5, y: 0.5)
    private let files: DemoFiles

    private static let bpm = 120.0
    private static let beat = 60 / bpm

    init(app: AppDelegate, output: URL, wide: Bool) {
        self.app = app
        self.output = output
        self.wide = wide
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
        if wide {
            let h = (screen.width * 9 / 16).rounded()
            frame = NSRect(x: screen.minX, y: (screen.midY - h / 2).rounded(), width: screen.width, height: h)
        } else {
            let w = (screen.height * 9 / 16).rounded()
            frame = NSRect(x: (screen.midX - w / 2).rounded(), y: screen.minY, width: w, height: screen.height)
        }
        files = DemoFiles.make()
        stage = Demo.window(frame, level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1))
        overlay = Demo.window(frame, level: NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2))
        overlay.ignoresMouseEvents = true
        build()
    }

    // MARK: - Script (120 BPM, one beat = 0.5 s)

    func run() async {
        app.chime = false
        app.panel.appearance = NSAppearance(named: .darkAqua)
        stage.orderFrontRegardless()
        overlay.orderFrontRegardless()
        await finder.loadIcons(files)
        do {
            try await recorder.start(frame: frame, to: output)
        } catch {
            fputs("Recording failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        recStart = CACurrentMediaTime()
        keyframe()
        await pause(0.4)
        t0 = CACurrentMediaTime()
        trimStart = t0 - recStart + 0.09  // the video opens mid-slam, so frame one already says something
        sound.startMusic()

        // Hook: three words on the beat.
        let mid = wide ? frame.height * 0.52 : frame.height * 0.56
        let big: CGFloat = wide ? 92 : 64
        slam("Converting files", size: big, y: mid + big * 1.2, animated: false)
        await at(1.5); slam("shouldn't take", size: big, y: mid)
        await at(3); slam("five apps.", size: big, y: mid - big * 1.2, color: .systemPink)
        await at(5.25); clearType()

        // The desktop arrives on the beat drop.
        await at(6)
        sound.play(.whoosh)
        finder.appear()
        fade(keys, to: 1)
        fade(cursor, to: 1)

        // 1. Shift-drag a photo: formats.
        await at(7); setCaption("Drag, then hold ⇧ Shift")
        await glide(to: finder.center(of: files.photo), beats: 1.2)
        await at(8.5); await grab([files.photo])
        let open1 = openPoint(from: point)
        await glide(to: open1, beats: 0.8)
        openWheel([files.photo])
        await at(10.5); await glide(to: tile(named: "JPG"), beats: 0.8)
        await at(11.5); await glide(to: tile(named: "TIFF"), beats: 0.8)
        await at(12.5); await glide(to: tile(named: "PNG"), beats: 0.8)

        // 2. Option: tools.
        await at(14); setCaption("Tap ⌥ for tools")
        tap(optionKey); app.panel.ring.showTools(); sound.play(.swap)
        await at(15); await glide(to: tile(named: "Compress"), beats: 0.8)
        await at(16); await glide(to: tile(named: "Resize 50%"), beats: 0.8)

        // 3. Shift back, drop on PNG.
        await at(17.5); setCaption("⇧ back to formats, let go")
        tap(optionKey, down: false); app.panel.ring.showFormats(); sound.play(.swap)
        await at(18.5); await glide(to: tile(named: "PNG"), beats: 0.8)
        await at(20); drop(expect: files.output("photo.png"))
        await at(21); sound.play(.chime); setCaption("Done. Right beside the original.")

        // Montage: three more real conversions.
        await at(23.5); chip("Video → GIF")
        await quick(files.clip, wheel: [files.clip], target: "GIF", tools: false, output: "clip.gif", start: 24)
        await at(31.5); chip("Crop it exactly")
        await cropDemo(start: 32)
        offset += Demo.cropExtra  // the crop editor scene runs longer; everything after shifts
        await at(39.5); chip("Merge photos into one PDF")
        await quick(files.trips[0], wheel: files.trips, target: "Merge PDF", tools: true, output: "Images.pdf", start: 40)

        // Values.
        await at(48)
        setCaption(nil)
        clearChip()
        finder.leave()
        fade(keys, to: 0)
        fade(cursor, to: 0)
        await at(49); slam("100% offline.", size: big * 0.82, y: mid + big)
        await at(50.5); slam("No uploads. No accounts.", size: big * 0.5, y: mid)
        await at(52); slam("Free.", size: big * 1.15, y: mid - big * 1.25, color: .systemGreen)
        await at(54); clearType()

        // End card.
        await at(54.5); endCard()
        await at(62)
        sound.fadeOut()
        await pause(1.2)
        try? await recorder.stop()
        try? JSONSerialization.data(withJSONObject: ["frames": camera, "start": trimStart, "width": frame.width, "height": frame.height])
            .write(to: output.deletingPathExtension().appendingPathExtension("camera.json"))
        exit(0)
    }

    /// One montage example: grab the file(s), open the wheel, maybe swap to tools, drop on `target`.
    private func quick(_ first: URL, wheel urls: [URL], target: String, tools: Bool, output: String, start b: Double) async {
        await at(b); await glide(to: finder.center(of: first), beats: 1)
        if urls.count > 1 { finder.select(urls); sound.play(.tick) }
        await at(b + 1.5); await grab(urls)
        await glide(to: openPoint(from: point), beats: 0.8)
        openWheel(urls)
        if tools {
            await at(b + 3.5); tap(optionKey); app.panel.ring.showTools(); sound.play(.swap)
        }
        await at(b + 4.5); await glide(to: tile(named: target), beats: 1)
        await at(b + 6); drop(expect: files.output(output))
        if tools { tap(optionKey, down: false) }
        await at(b + 7); sound.play(.chime)
    }

    static let cropExtra = demoCropExtra

    /// The Crop tool, live: drop the photo on Crop, then in the real editor pick 4:5, slide the size to 60 % and save.
    private func cropDemo(start b: Double) async {
        CropEditor.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue)
        CropEditor.width = wide ? 640 : frame.width - 40
        await at(b); await glide(to: finder.center(of: files.photo), beats: 1)
        await at(b + 1.5); await grab([files.photo])
        await glide(to: openPoint(from: point), beats: 0.8)
        openWheel([files.photo])
        await at(b + 3.5); tap(optionKey); app.panel.ring.showTools(); sound.play(.swap)
        await at(b + 4.5); await glide(to: tile(named: "Crop"), beats: 1)
        let landing = finder.nextSlotCenter()
        app.showsToast = false
        await at(b + 6); drop(expect: nil)
        tap(optionKey, down: false)

        // The real editor opens; drive it like a person would.
        var editor: CropEditor?
        for _ in 0..<60 where editor == nil {
            editor = CropEditor.current
            if editor == nil { await pause(0.05) }
        }
        guard let editor else { app.showsToast = true; return }
        sound.play(.whoosh)
        await at(b + 7); await glide(to: local(editor.point(ofAspect: 3)), beats: 0.8)
        await at(b + 8); ripple(); sound.play(.tick); editor.selectAspect(3)
        await at(b + 9); await glide(to: local(editor.point(forPercent: 100)), beats: 0.8)
        await at(b + 10); ripple(); sound.play(.tick)
        await glide(to: local(editor.point(forPercent: 60)), beats: 1.4) {
            editor.setPercent(editor.percent(atScreenX: self.screen(self.point).x))
        }
        await at(b + 12); await glide(to: local(editor.pointOfSave), beats: 0.8)
        await at(b + 13); ripple(); sound.play(.pop); editor.save()
        await pause(0.45)
        await finder.add(files.output("photo cropped.heic"))
        app.showsToast = true
        app.hud.done("photo cropped.heic", near: screen(NSPoint(x: landing.x, y: landing.y + 70)))
        sound.play(.chime)
    }

    private func local(_ p: NSPoint) -> NSPoint { NSPoint(x: p.x - frame.minX, y: p.y - frame.minY) }

    // MARK: - Actions

    private func grab(_ urls: [URL]) async {
        held = urls
        ripple()
        finder.select(urls)
        carried.image = finder.dragImage(for: urls)
        carried.frame.size = carried.image?.size ?? NSSize(width: 64, height: 64)
        placeCursor()
        fade(carried, to: 0.9)
        badgeView.alphaValue = 1
        finder.dim(urls, true)
        await pause(0.15)
    }

    private func openWheel(_ urls: [URL]) {
        shiftKey.down = true
        sound.play(.key)
        app.show(urls, at: screen(point))
        sound.play(.whoosh)
        lastHover = nil
        guard wide else { return }
        let c = NSPoint(x: app.panel.frame.midX - frame.minX, y: app.panel.frame.midY - frame.minY)
        let mid = NSPoint(x: frame.width / 2, y: frame.height / 2)
        zoomTo(1.1, focus: NSPoint(x: mid.x + (c.x - mid.x) * 0.35, y: mid.y + (c.y - mid.y) * 0.35), over: 0.7)
    }

    private func drop(expect result: URL?, landAfter seconds: Double = 0.9) {
        ripple()
        sound.play(.pop)
        if let i = app.panel.ring.hovered {
            app.lastPoint = screen(point)
            app.perform(app.panel.ring.actions[i], held)
        }
        shiftKey.down = false
        fade(carried, to: 0)
        badgeView.alphaValue = 0
        finder.dim(held, false)
        finder.select([])
        if wide { zoomTo(1, focus: NSPoint(x: frame.width / 2, y: frame.height / 2), over: 0.8) }
        guard let result else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            await finder.add(result)
        }
    }

    private func tap(_ key: KeyCap, down: Bool = true) {
        key.down = down
        if down { sound.play(.key) }
    }

    // MARK: - Pointer

    private func glide(to target: NSPoint, beats: Double, onStep: (() -> Void)? = nil) async {
        let start = point, duration = beats * Demo.beat, frames = max(1, Int(duration * 60))
        for f in 1...frames {
            let t = Double(f) / Double(frames)
            let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            point = NSPoint(x: start.x + (target.x - start.x) * e, y: start.y + (target.y - start.y) * e)
            placeCursor()
            onStep?()
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func placeCursor() {
        // The arrow's tip (its hotspot) sits 4 px in from the image's top-left corner.
        cursor.frame.origin = NSPoint(x: point.x - 4, y: point.y - cursor.frame.height + 4)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        badgeView.frame.origin = NSPoint(x: point.x + 10, y: point.y - 40)
        CATransaction.commit()
        carried.frame.origin = NSPoint(x: point.x - carried.frame.width / 2 + 8, y: point.y - carried.frame.height - 10)
        let panel = app.panel
        guard panel.isVisible else { return }
        let local = panel.ring.convert(panel.convertPoint(fromScreen: screen(point)), from: nil)
        let hit = panel.ring.index(at: local)
        panel.ring.hovered = hit
        if hit != nil, hit != lastHover { sound.play(.tick) }
        lastHover = hit
    }

    private func ripple() {
        guard let host = overlay.contentView?.layer else { return }
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -18, y: -18, width: 36, height: 36), transform: nil)
        ring.fillColor = NSColor.white.withAlphaComponent(0.25).cgColor
        ring.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        ring.lineWidth = 2
        ring.position = CGPoint(x: point.x, y: point.y)
        host.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1.6
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fadeOut]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.opacity = 0
        ring.add(group, forKey: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ring.removeFromSuperlayer() }
    }

    private func tile(named title: String) -> NSPoint {
        let ring = app.panel.ring, n = max(ring.actions.count, 1)
        let i = ring.actions.firstIndex { $0.title == title } ?? 0
        let a = CGFloat(i) * 2 * .pi / CGFloat(n), r: CGFloat = 104
        let c = NSPoint(x: app.panel.frame.midX - frame.minX, y: app.panel.frame.midY - frame.minY)
        return NSPoint(x: c.x + r * sin(a), y: c.y + r * cos(a))
    }

    /// Where the wheel opens after a short drag: up and away from the window, kept clear of the stage edges.
    private func openPoint(from p: NSPoint) -> NSPoint {
        let x = min(max(p.x + (wide ? -60 : 0), 200), frame.width - 200)
        let y = min(max(p.y + (wide ? 40 : 150), 210), frame.height - 230)
        return NSPoint(x: x, y: y)
    }

    private func screen(_ p: NSPoint) -> NSPoint { NSPoint(x: frame.minX + p.x, y: frame.minY + p.y) }

    // MARK: - Type

    private func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> CATextLayer {
        let l = CATextLayer()
        l.string = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: -size * 0.025])
        l.alignmentMode = .center
        l.contentsScale = 2
        l.isWrapped = true
        return l
    }

    private func slam(_ string: String, size: CGFloat, y: CGFloat, color: NSColor = .white, animated: Bool = true) {
        let l = text(string, size: size, weight: .heavy, color: color)
        let w = textWidth
        l.bounds = CGRect(x: 0, y: 0, width: w, height: size * 1.3)
        l.position = CGPoint(x: textCenterX, y: y)
        guard animated else {
            // No implicit fade-in either: the very first frame shows the word crisp and solid.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            typeView.layer?.addSublayer(l)
            CATransaction.commit()
            sound.play(.thump)
            return
        }
        typeView.layer?.addSublayer(l)
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.45
        scale.toValue = 1
        scale.damping = 15
        scale.stiffness = 300
        scale.duration = scale.settlingDuration
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0
        appear.toValue = 1
        appear.duration = 0.1
        l.add(scale, forKey: nil)
        l.add(appear, forKey: nil)
        sound.play(.thump)
    }

    private func clearType() {
        for l in typeView.layer?.sublayers ?? [] where l.name != "keep" {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
            l.opacity = 0
            l.position.y += 40
            CATransaction.commit()
        }
        sound.play(.whoosh)
    }

    private var textWidth: CGFloat { wide ? frame.width * 0.9 : frame.width - 32 }
    private var textCenterX: CGFloat { frame.width / 2 }

    /// The small instruction line: top of the stage when vertical, left column when wide.
    private func setCaption(_ string: String?) {
        let replacing = caption != nil
        if let old = caption {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
            old.opacity = 0
            CATransaction.commit()
        }
        caption = nil
        guard let string else { return }
        let size: CGFloat = wide ? 46 : 30
        let l = text(string, size: size, weight: .bold, color: .white)
        l.name = "keep"
        l.alignmentMode = wide ? .left : .center
        if wide {
            l.bounds = CGRect(x: 0, y: 0, width: frame.width * 0.4, height: size * 2.6)
            l.position = CGPoint(x: frame.width * 0.06 + frame.width * 0.2, y: frame.height * 0.6)
        } else {
            l.bounds = CGRect(x: 0, y: 0, width: frame.width - 40, height: size * 2.6)
            l.position = CGPoint(x: frame.width / 2, y: frame.height - 150)
        }
        typeView.layer?.addSublayer(l)
        // When replacing a caption, wait for the old one to fade so the two never overlap.
        let begin = CACurrentMediaTime() + (replacing ? 0.2 : 0)
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = l.position.y - 24
        rise.toValue = l.position.y
        rise.duration = 0.35
        rise.beginTime = begin
        rise.fillMode = .backwards
        rise.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0
        appear.toValue = 1
        appear.duration = 0.25
        appear.beginTime = begin
        appear.fillMode = .backwards
        l.add(rise, forKey: nil)
        l.add(appear, forKey: nil)
        caption = l
    }

    private var chipLayer: CALayer?

    private func chip(_ string: String) {
        clearChip()
        let size: CGFloat = wide ? 22 : 18
        let label = text(string.uppercased(), size: size, weight: .bold, color: .white)
        let w = ((label.string as? NSAttributedString)?.size().width ?? 200).rounded() + 44
        let pill = CALayer()
        pill.name = "keep"
        pill.backgroundColor = NSColor.controlAccentColor.cgColor
        pill.cornerRadius = size + 2
        pill.bounds = CGRect(x: 0, y: 0, width: w, height: (size + 2) * 2)
        pill.position = wide ? CGPoint(x: frame.width * 0.06 + w / 2, y: frame.height * 0.78) : CGPoint(x: frame.width / 2, y: frame.height - 82)
        label.bounds = CGRect(x: 0, y: 0, width: w, height: size * 1.3)
        label.position = CGPoint(x: w / 2, y: size + 2)
        pill.addSublayer(label)
        typeView.layer?.addSublayer(pill)
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.4
        pop.toValue = 1
        pop.damping = 13
        pop.stiffness = 320
        pop.duration = pop.settlingDuration
        pill.add(pop, forKey: nil)
        sound.play(.thump)
        chipLayer = pill
        setCaption(nil)
    }

    private func clearChip() {
        guard let old = chipLayer else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
        old.opacity = 0
        CATransaction.commit()
        chipLayer = nil
    }

    private func endCard() {
        guard let host = typeView.layer else { return }
        let icon = CALayer()
        icon.contents = NSApp.applicationIconImage
        icon.contentsGravity = .resizeAspect
        let side: CGFloat = wide ? 210 : 170
        let cy = frame.height * (wide ? 0.6 : 0.6)
        icon.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        icon.position = CGPoint(x: frame.width / 2, y: cy)
        icon.shadowColor = NSColor.black.cgColor
        icon.shadowOpacity = 0.4
        icon.shadowRadius = 24
        icon.shadowOffset = CGSize(width: 0, height: -10)
        host.addSublayer(icon)
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.2
        pop.toValue = 1
        pop.damping = 10
        pop.stiffness = 180
        pop.duration = pop.settlingDuration
        icon.add(pop, forKey: nil)
        sound.play(.boom)

        let lines: [(String, CGFloat, NSFont.Weight, NSColor, CGFloat)] = [
            ("Shiftvert", wide ? 96 : 72, .heavy, .white, side / 2 + (wide ? 70 : 56)),
            ("Drag. Hold ⇧. Done.", wide ? 36 : 28, .semibold, NSColor(white: 1, alpha: 0.85), side / 2 + (wide ? 135 : 108)),
            ("Free  ·  Private  ·  Open source  ·  for Mac", wide ? 22 : 17, .semibold, NSColor(white: 1, alpha: 0.6), side / 2 + (wide ? 185 : 148)),
            ("shiftvert.com", wide ? 30 : 24, .bold, NSColor.white, side / 2 + (wide ? 240 : 196)),
        ]
        for (i, (s, size, weight, color, dy)) in lines.enumerated() {
            let l = text(s, size: size, weight: weight, color: color)
            l.bounds = CGRect(x: 0, y: 0, width: frame.width - 40, height: size * 1.3)
            l.position = CGPoint(x: frame.width / 2, y: cy - dy)
            l.opacity = 0
            host.addSublayer(l)
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.beginTime = CACurrentMediaTime() + 0.25 + Double(i) * 0.2
            appear.duration = 0.4
            appear.fillMode = .both
            appear.isRemovedOnCompletion = false
            let rise = CABasicAnimation(keyPath: "position.y")
            rise.fromValue = l.position.y - 20
            rise.toValue = l.position.y
            rise.beginTime = appear.beginTime
            rise.duration = 0.5
            rise.fillMode = .both
            rise.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            l.add(appear, forKey: nil)
            l.add(rise, forKey: nil)
        }
        zoomTo(1.06, focus: NSPoint(x: frame.width / 2, y: cy - 60), over: 3.5)
    }

    // MARK: - Camera (applied in post by scripts/export-video.swift)

    private func keyframe() {
        camera.append(["t": CACurrentMediaTime() - recStart, "s": zoom.s, "x": zoom.x, "y": zoom.y])
    }

    /// Eases the virtual camera to a zoom level around a stage point, written as many small linear steps.
    private func zoomTo(_ s: Double, focus: NSPoint, over seconds: Double) {
        let from = zoom, to = (s: s, x: Double(focus.x / frame.width), y: Double(1 - focus.y / frame.height))
        let start = CACurrentMediaTime() - recStart, steps = 12
        if let last = camera.last, let lt = last["t"], lt < start {
            camera.append(["t": start, "s": from.s, "x": from.x, "y": from.y])
        }
        for i in 1...steps {
            let t = Double(i) / Double(steps), e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            camera.append(["t": start + seconds * t, "s": from.s + (to.s - from.s) * e,
                           "x": from.x + (to.x - from.x) * e, "y": from.y + (to.y - from.y) * e])
        }
        zoom = to
    }

    // MARK: - Timing

    private var offset = 0.0

    private func at(_ beat: Double) async {
        let wait = t0 + (beat + offset) * Demo.beat - CACurrentMediaTime()
        if wait > 0 { try? await Task.sleep(for: .milliseconds(Int(wait * 1000))) }
    }

    private func pause(_ seconds: Double) async { try? await Task.sleep(for: .milliseconds(Int(seconds * 1000))) }

    private func fade(_ view: NSView, to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; view.animator().alphaValue = alpha }
    }

    // MARK: - Build

    private func build() {
        let size = frame.size
        let art = DemoArt.wallpaper(width: Int(size.width * 2), height: Int(size.height * 2))
        let wall = CALayer()
        wall.contents = art
        wall.contentsGravity = .resizeAspectFill
        root.frame = NSRect(origin: .zero, size: size)
        root.layer = wall
        root.wantsLayer = true
        // A slow push on the wallpaper keeps every frame alive.
        let drift = CABasicAnimation(keyPath: "transform.scale")
        drift.fromValue = 1.0
        drift.toValue = 1.08
        drift.duration = 40
        wall.add(drift, forKey: "drift")
        stage.contentView = root

        let menu = MenuBar(frame: NSRect(x: 0, y: size.height - 30, width: size.width, height: 30))
        root.addSubview(menu)

        finder.frame = wide
            ? NSRect(x: size.width * 0.5, y: size.height * 0.17, width: size.width * 0.44, height: size.height * 0.56)
            : NSRect(x: 22, y: size.height * 0.125, width: size.width - 44, height: 404)
        finder.layoutGrid(columns: wide ? 5 : 4)
        finder.alphaValue = 0
        root.addSubview(finder)

        keys.addArrangedSubview(shiftKey)
        keys.addArrangedSubview(optionKey)
        keys.spacing = 14
        keys.frame = wide
            ? NSRect(x: size.width * 0.06, y: size.height * 0.3, width: 160, height: 60)
            : NSRect(x: size.width / 2 - 80, y: 40, width: 160, height: 60)
        keys.alphaValue = 0
        root.addSubview(keys)

        typeView.frame = root.bounds
        typeView.layer = CALayer()
        typeView.wantsLayer = true
        root.addSubview(typeView)

        let pointerLayer = NSView(frame: NSRect(origin: .zero, size: size))
        pointerLayer.layer = CALayer()
        pointerLayer.wantsLayer = true
        carried.imageScaling = .scaleProportionallyUpOrDown
        carried.alphaValue = 0
        cursor.image = Demo.arrow
        cursor.imageScaling = .scaleNone
        cursor.frame.size = Demo.arrow.size
        cursor.alphaValue = 0
        pointerLayer.addSubview(carried)
        pointerLayer.addSubview(cursor)
        // Finder's green "+" copy badge, shown while a file is being dragged.
        badgeView.wantsLayer = true
        badge.cornerRadius = 10
        badge.backgroundColor = NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1).cgColor
        badge.borderColor = NSColor.white.cgColor
        badge.borderWidth = 1.5
        let plus = CAShapeLayer()
        let pp = CGMutablePath()
        pp.move(to: CGPoint(x: 10, y: 5)); pp.addLine(to: CGPoint(x: 10, y: 15))
        pp.move(to: CGPoint(x: 5, y: 10)); pp.addLine(to: CGPoint(x: 15, y: 10))
        plus.path = pp
        plus.strokeColor = NSColor.white.cgColor
        plus.lineWidth = 2.4
        plus.lineCap = .round
        badge.addSublayer(plus)
        badgeView.alphaValue = 0
        pointerLayer.addSubview(badgeView)
        overlay.contentView = pointerLayer
        point = NSPoint(x: size.width * 0.82, y: size.height * 0.08)
        placeCursor()
    }

    /// A crisp, vector macOS-style arrow (black with a white rim and soft shadow), 1.6× the usual size.
    private static let arrow: NSImage = {
        let k: CGFloat = 1.6, pad: CGFloat = 4
        return NSImage(size: NSSize(width: 17 * k + pad * 2, height: 25 * k + pad * 2), flipped: true) { _ in
            let pts: [(CGFloat, CGFloat)] = [(1.5, 1.5), (1.5, 19.7), (6.1, 15.3), (9.2, 22.3), (12.2, 21), (9.2, 14.2), (15.5, 14.2)]
            let path = NSBezierPath()
            for (i, (x, y)) in pts.enumerated() {
                let p = NSPoint(x: pad + (x - 1.5) * k, y: pad + (y - 1.5) * k)
                if i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.close()
            path.lineJoinStyle = .round
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1.5)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            NSColor.white.setFill()
            path.lineWidth = 3.2
            NSColor.white.setStroke()
            path.stroke()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.setFill()
            path.fill()
            return true
        }
    }()

    private static func window(_ rect: NSRect, level: NSWindow.Level) -> NSWindow {
        let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = level
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.appearance = NSAppearance(named: .darkAqua)
        return w
    }
}

// MARK: - Recording (only Shiftvert's own windows, with its own sound)

@available(macOS 15, *)
final class DemoRecorder: NSObject, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var finished: CheckedContinuation<Void, Never>?

    @MainActor func start(frame: NSRect, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw Fail("No display to record.")
        }
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, including: me, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: frame.minX, y: CGFloat(display.height) - frame.maxY, width: frame.width, height: frame.height)
        config.width = Int(frame.width * 2)
        config.height = Int(frame.height * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let rc = SCRecordingOutputConfiguration()
        rc.outputURL = url
        rc.outputFileType = .mov
        rc.videoCodecType = .h264
        try stream.addRecordingOutput(SCRecordingOutput(configuration: rc, delegate: self))
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws {
        await withCheckedContinuation { c in
            finished = c
            Task { try? await stream?.stopCapture() }
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { finished?.resume(); finished = nil }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        fputs("Recording error: \(error.localizedDescription)\n", stderr)
        finished?.resume()
        finished = nil
    }
}

// MARK: - Sound: original music and effects, synthesized

/// Extra beats the crop-editor scene adds; the music's breakdown and finale move with it.
let demoCropExtra = 7.0

@MainActor final class DemoSound {
    enum Effect: CaseIterable { case tick, whoosh, key, pop, chime, thump, swap, boom }

    private let engine = AVAudioEngine()
    private let music = AVAudioPlayerNode()
    private var voices: [AVAudioPlayerNode] = []
    private var next = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private lazy var song = Synth.music(format: format, beats: 72 + Int(demoCropExtra) - 4, bpm: 120,
                                        breakdown: 48 + demoCropExtra, finale: 54.5 + demoCropExtra)

    init() {
        engine.attach(music)
        engine.connect(music, to: engine.mainMixerNode, format: format)
        for _ in 0..<8 {
            let v = AVAudioPlayerNode()
            engine.attach(v)
            engine.connect(v, to: engine.mainMixerNode, format: format)
            voices.append(v)
        }
        for e in Effect.allCases { buffers[e] = Synth.effect(e, format: format) }
        _ = song
        engine.mainMixerNode.outputVolume = 0.8
        try? engine.start()
    }

    func startMusic() {
        music.scheduleBuffer(song, at: nil)
        music.play()
    }

    func fadeOut() {
        Task { @MainActor in
            for i in stride(from: 10, through: 0, by: -1) {
                engine.mainMixerNode.outputVolume = 0.8 * Float(i) / 10
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    func play(_ e: Effect) {
        guard let b = buffers[e] else { return }
        let v = voices[next]
        next = (next + 1) % voices.count
        v.stop()
        v.scheduleBuffer(b, at: nil)
        v.play()
    }
}

enum Synth {
    static func buffer(_ format: AVAudioFormat, seconds: Double, _ fill: (Int, Double) -> (Float, Float)) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(seconds * format.sampleRate)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        b.frameLength = n
        let l = b.floatChannelData![0], r = b.floatChannelData![1], sr = format.sampleRate
        for i in 0..<Int(n) {
            let (a, c) = fill(i, Double(i) / sr)
            l[i] = a
            r[i] = c
        }
        return b
    }

    static func effect(_ e: DemoSound.Effect, format: AVAudioFormat) -> AVAudioPCMBuffer {
        var seed: UInt32 = 0x9E3779B9
        func noise() -> Double {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return Double(seed) / Double(UInt32.max) * 2 - 1
        }
        switch e {
        case .tick:
            return buffer(format, seconds: 0.05) { _, t in
                let v = Float(sin(2 * .pi * 2600 * t) * exp(-t * 110) * 0.16); return (v, v) }
        case .key:
            return buffer(format, seconds: 0.06) { _, t in
                let v = Float((noise() * exp(-t * 260) * 0.5 + sin(2 * .pi * 1400 * t) * exp(-t * 120) * 0.25) * 0.5); return (v, v) }
        case .pop:
            return buffer(format, seconds: 0.16) { _, t in
                let f = 300 + 700 * exp(-t * 40)
                let v = Float(sin(2 * .pi * f * t) * exp(-t * 28) * 0.45); return (v, v) }
        case .chime:
            return buffer(format, seconds: 1.2) { _, t in
                let a = sin(2 * .pi * 1318.5 * t) * exp(-t * 4.5), b = sin(2 * .pi * 1975.5 * t) * exp(-t * 6) * 0.6
                let c = sin(2 * .pi * 2637 * t) * exp(-t * 9) * 0.25
                let v = Float((a + b + c) * 0.16 * min(1, t * 400)); return (v, Float(Double(v) * 0.92)) }
        case .whoosh:
            var lp = 0.0
            return buffer(format, seconds: 0.45) { _, t in
                let env = sin(.pi * min(1, t / 0.45)) * sin(.pi * min(1, t / 0.45))
                let cutoff = 0.04 + 0.25 * t / 0.45
                lp += cutoff * (noise() - lp)
                let v = Float(lp * env * 0.55); return (v * 0.9, v) }
        case .thump:
            return buffer(format, seconds: 0.3) { _, t in
                let f = 45 + 90 * exp(-t * 30)
                let v = Float((sin(2 * .pi * f * t) * exp(-t * 11) * 0.48 + noise() * exp(-t * 90) * 0.1)); return (v, v) }
        case .swap:
            return buffer(format, seconds: 0.18) { _, t in
                let f = 700 + 900 * t / 0.18
                let v = Float(sin(2 * .pi * f * t) * sin(.pi * t / 0.18) * 0.12); return (v, v) }
        case .boom:
            var lp = 0.0
            return buffer(format, seconds: 2.2) { _, t in
                let f = 38 + 60 * exp(-t * 6)
                lp += 0.02 * (noise() - lp)
                let v = Float(sin(2 * .pi * f * t) * exp(-t * 2.2) * 0.42 + lp * exp(-t * 3) * 0.35)
                return (v, v) }
        }
    }

    /// An original track at 120 BPM, arranged to the demo's beat map: a soft pad intro under the hook, a riser into
    /// the drop when the desktop arrives (beat 6), kick, sub, hats and sidechain pump through the walkthrough, claps
    /// and a plucked arpeggio with ping-pong echo for the montage, a breakdown under the closing claims, and a bright
    /// final chord on the logo.
    static func music(format: AVAudioFormat, beats: Int, bpm: Double, breakdown: Double, finale: Double) -> AVAudioPCMBuffer {
        let sr = format.sampleRate, spb = 60 / bpm, n = Int(Double(beats) * spb * sr)
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        out.frameLength = AVAudioFrameCount(n)
        let L = out.floatChannelData![0], R = out.floatChannelData![1]
        let drop = 6.0, arpIn = 14.0, clapsIn = 23.0
        // Am7, Fmaj7, Cadd9, G6: warm, open voicings.
        let chords: [[Double]] = [[220, 261.63, 329.63, 392], [174.61, 220, 261.63, 329.63],
                                  [261.63, 329.63, 392, 587.33], [196, 246.94, 293.66, 329.63]]
        let roots: [Double] = [55, 43.65, 65.41, 49]
        let final: [Double] = [130.81, 196, 261.63, 329.63, 493.88, 587.33]  // Cmaj9 spread
        let pattern = [0, 2, 1, 3, 2, 1, 3, 2]
        var arpL = [Double](repeating: 0, count: n), arpR = arpL
        var seed: UInt32 = 12345
        func noise() -> Double { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return Double(seed) / Double(UInt32.max) * 2 - 1 }
        var padL = 0.0, padR = 0.0, hp = 0.0, c1 = 0.0, c2 = 0.0, rise = 0.0

        for i in 0..<n {
            let t = Double(i) / sr, beat = t / spb, bi = Int(beat), within = (beat - Double(bi)) * spb
            let notes = chords[(bi / 8) % 4]
            // Pad, low-passed for warmth, ducked by the kick while the groove plays.
            var pl = 0.0, pr = 0.0
            for f in notes {
                pl += sin(2 * .pi * f * t) + 0.3 * sin(2 * .pi * 2 * f * 1.002 * t)
                pr += sin(2 * .pi * f * 1.003 * t) + 0.3 * sin(2 * .pi * 2 * f * t)
            }
            padL += 0.07 * (pl - padL)
            padR += 0.07 * (pr - padR)
            let groove = beat >= drop && beat < breakdown
            let pump = groove ? 1 - 0.6 * exp(-within * 7) : 1
            let padFade = beat < finale ? 1 : max(0, 1 - (beat - finale) / 2)
            var l = padL * 0.026 * min(1, t / 1.5) * pump * padFade, r = padR * 0.026 * min(1, t / 1.5) * pump * padFade

            if groove {
                let kick = sin(2 * .pi * (46 + 120 * exp(-within * 35)) * within) * exp(-within * 8) * 0.62
                let sub = sin(2 * .pi * roots[(bi / 8) % 4] * t) * min(1, within * 20) * exp(-within * 2.2) * 0.2
                var hat = 0.0
                if within >= spb / 2 {
                    let x = noise()
                    hat = (x - hp) * exp(-(within - spb / 2) * 60) * 0.055
                    hp = x
                }
                var clap = 0.0
                if beat >= clapsIn, bi % 2 == 1 {
                    let x = noise()
                    c1 += 0.35 * (x - c1)
                    c2 += 0.05 * (c1 - c2)
                    clap = (c1 - c2) * (exp(-within * 26) + 0.5 * exp(-max(0, within - 0.012) * 40)) * 0.42
                }
                l += kick + sub + hat * 0.8 + clap
                r += kick + sub + hat + clap * 0.9
            }
            // Risers into the drop and into the finale.
            for (a, b) in [(drop - 2, drop), (finale - 2.5, finale)] where beat >= a && beat < b {
                let x = (beat - a) / (b - a)
                rise += (0.02 + 0.3 * x) * (noise() - rise)
                l += rise * x * x * 0.3
                r += rise * x * x * 0.3
            }
            // Finale: one bright chord that rings out under the logo.
            if beat >= finale {
                let tf = t - finale * spb, env = exp(-tf * 0.55) * min(1, tf * 60)
                for (k, f) in final.enumerated() {
                    let v = (sin(2 * .pi * f * tf) + 0.2 * sin(2 * .pi * 2 * f * tf)) * env * 0.03
                    l += k % 2 == 0 ? v : v * 0.8
                    r += k % 2 == 0 ? v * 0.8 : v
                }
            }
            // Arpeggio: plucked chord tones on eighth notes, an octave up.
            if beat >= arpIn && beat < finale {
                let e = beat * 2, ei = Int(e), te = (e - Double(ei)) * spb / 2
                let f = notes[pattern[ei % 8]] * 2
                let v = (sin(2 * .pi * f * te) + 0.22 * sin(2 * .pi * 2 * f * te)) * exp(-te * 9) * (beat >= breakdown ? 0.06 : 0.045)
                arpL[i] = v
                arpR[i] = v
            }
            L[i] = Float(l)
            R[i] = Float(r)
        }
        // Ping-pong echo on the arpeggio (dotted eighth), then a gentle soft-clip master.
        let d = Int(0.75 * spb * sr)
        for i in d..<n {
            arpL[i] += arpR[i - d] * 0.42
            arpR[i] += arpL[i - d] * 0.42
        }
        let total = Double(n) / sr
        for i in 0..<n {
            let t = Double(i) / sr, fade = min(1, max(0, (total - t) / 2.5))
            L[i] = Float(tanh((Double(L[i]) + arpL[i]) * 1.15) * 0.46 * fade)
            R[i] = Float(tanh((Double(R[i]) + arpR[i]) * 1.15) * 0.46 * fade)
        }
        return out
    }
}

// MARK: - Demo files (all generated, all real)

struct DemoFiles {
    let dir: URL
    let photo: URL, clip: URL, pdf: URL, trips: [URL]

    func output(_ name: String) -> URL { dir.appendingPathComponent(name) }

    static func make() -> DemoFiles {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ShiftvertDemo", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let photo = dir.appendingPathComponent("photo.heic")
        DemoArt.save(DemoArt.scene(.sunset), to: photo, type: .heic)
        let trips = (1...3).map { dir.appendingPathComponent("trip \($0).jpg") }
        for (i, url) in trips.enumerated() { DemoArt.save(DemoArt.scene([.ocean, .forest, .dusk][i]), to: url, type: .jpeg) }
        let pdf = dir.appendingPathComponent("report.pdf")
        let doc = PDFDocument()
        for s in [DemoArt.Palette.dusk, .ocean] {
            if let page = PDFPage(image: NSImage(cgImage: DemoArt.scene(s), size: NSSize(width: 640, height: 480))) { doc.insert(page, at: doc.pageCount) }
        }
        doc.write(to: pdf)
        let clip = dir.appendingPathComponent("clip.mov")
        DemoArt.movie(to: clip)
        return DemoFiles(dir: dir, photo: photo, clip: clip, pdf: pdf, trips: trips)
    }
}

enum DemoArt {
    enum Palette { case sunset, ocean, forest, dusk }

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    static func scene(_ p: Palette, sun: CGFloat = 0.62, width: Int = 640, height: Int = 480) -> CGImage {
        let (sky, hill1, hill2): ([CGColor], CGColor, CGColor) = {
            switch p {
            case .sunset: return ([rgb(1, 0.7, 0.4), rgb(0.95, 0.38, 0.52), rgb(0.33, 0.2, 0.62)], rgb(0.36, 0.17, 0.48), rgb(0.2, 0.1, 0.34))
            case .ocean: return ([rgb(0.6, 0.9, 1), rgb(0.3, 0.6, 0.95), rgb(0.12, 0.25, 0.6)], rgb(0.1, 0.4, 0.6), rgb(0.05, 0.25, 0.45))
            case .forest: return ([rgb(0.98, 0.95, 0.75), rgb(0.6, 0.85, 0.65), rgb(0.2, 0.5, 0.45)], rgb(0.15, 0.45, 0.3), rgb(0.08, 0.3, 0.2))
            case .dusk: return ([rgb(1, 0.55, 0.45), rgb(0.6, 0.3, 0.6), rgb(0.12, 0.1, 0.35)], rgb(0.25, 0.12, 0.38), rgb(0.12, 0.06, 0.24))
            }
        }()
        let w = Double(width), h = Double(height)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.drawLinearGradient(CGGradient(colorsSpace: nil, colors: sky as CFArray, locations: [0, 0.45, 1])!,
                               start: .zero, end: CGPoint(x: 0, y: h), options: [])
        ctx.setFillColor(rgb(1, 0.93, 0.7))
        ctx.fillEllipse(in: CGRect(x: w * sun, y: h * 0.32, width: w * 0.22, height: w * 0.22))
        for (color, base, amp) in [(hill1, h * 0.36, h * 0.09), (hill2, h * 0.23, h * 0.12)] {
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: base))
            path.addCurve(to: CGPoint(x: w, y: base - h * 0.02), control1: CGPoint(x: w * 0.3, y: base + amp), control2: CGPoint(x: w * 0.65, y: base - amp))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(color)
            ctx.fillPath()
        }
        return ctx.makeImage()!
    }

    /// The stage backdrop: a deep dusk sky with a glowing horizon and layered hills.
    static func wallpaper(width: Int, height: Int) -> CGImage {
        let w = Double(width), h = Double(height)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [rgb(0.85, 0.36, 0.45), rgb(0.33, 0.16, 0.5), rgb(0.07, 0.05, 0.2), rgb(0.02, 0.02, 0.08)] as CFArray,
                                          locations: [0, 0.28, 0.65, 1])!, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        let glow = CGGradient(colorsSpace: nil, colors: [CGColor(srgbRed: 1, green: 0.62, blue: 0.45, alpha: 0.75), CGColor(srgbRed: 1, green: 0.4, blue: 0.5, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: w * 0.62, y: h * 0.22), startRadius: 0,
                               endCenter: CGPoint(x: w * 0.62, y: h * 0.22), endRadius: max(w, h) * 0.45, options: [])
        var seed: UInt32 = 7
        for _ in 0..<160 {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            let x = Double(seed % UInt32(width)), y = h * 0.45 + Double((seed >> 8) % UInt32(max(1, height / 2)))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: Double(seed % 70) / 100 + 0.15))
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: 2.2, height: 2.2))
        }
        for (color, base, amp) in [(rgb(0.24, 0.12, 0.4), h * 0.2, h * 0.06), (rgb(0.14, 0.07, 0.28), h * 0.13, h * 0.08), (rgb(0.07, 0.04, 0.16), h * 0.06, h * 0.06)] {
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: base))
            path.addCurve(to: CGPoint(x: w, y: base + h * 0.02), control1: CGPoint(x: w * 0.35, y: base + amp), control2: CGPoint(x: w * 0.7, y: base - amp))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(color)
            ctx.fillPath()
        }
        return ctx.makeImage()!
    }

    static func save(_ image: CGImage, to url: URL, type: UTType) {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(d, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(d)
    }

    /// A 2-second clip of the sun sliding across the sky (real H.264, so the GIF conversion is genuine).
    static func movie(to url: URL) {
        let w = 640, h = 360, fps: Int32 = 30, count = 60
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for i in 0..<count {
            while !input.isReadyForMoreMediaData { usleep(2000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let pb = buffer else { continue }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.draw(scene(.ocean, sun: 0.1 + 0.6 * CGFloat(i) / CGFloat(count), width: w, height: h), in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
    }
}

// MARK: - Stage pieces

/// A dark Finder window holding the demo files as a grid of real Quick Look thumbnails.
@MainActor final class FinderWindow: NSView {
    private var tiles: [URL: FileTile] = [:]
    private var order: [URL] = []
    private var columns = 4
    private let body = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.1, blue: 0.15, alpha: 0.93).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowRadius = 30
        layer?.shadowOffset = CGSize(width: 0, height: -14)
        addSubview(body)
    }
    required init?(coder: NSCoder) { fatalError() }

    func layoutGrid(columns: Int) {
        self.columns = columns
        subviews.filter { $0 !== body }.forEach { $0.removeFromSuperview() }
        let bar = NSView(frame: NSRect(x: 0, y: bounds.height - 46, width: bounds.width, height: 46))
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            let dot = NSView(frame: NSRect(x: 18 + i * 20, y: 17, width: 12, height: 12))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 6
            dot.layer?.backgroundColor = c.cgColor
            bar.addSubview(dot)
        }
        let title = NSTextField(labelWithString: "Downloads")
        title.font = .systemFont(ofSize: 14, weight: .bold)
        title.textColor = NSColor(white: 1, alpha: 0.9)
        title.frame = NSRect(x: 92, y: 13, width: 200, height: 20)
        bar.addSubview(title)
        let line = NSView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        bar.addSubview(line)
        addSubview(bar)
        body.frame = NSRect(x: 12, y: 10, width: bounds.width - 24, height: bounds.height - 60)
    }

    func loadIcons(_ files: DemoFiles) async {
        for url in [files.photo, files.clip, files.pdf] + files.trips { await add(url, animated: false) }
    }

    private func slot(_ i: Int) -> NSRect {
        let w = body.bounds.width / CGFloat(columns), h: CGFloat = 112
        return NSRect(x: CGFloat(i % columns) * w + (w - 104) / 2, y: body.bounds.height - CGFloat(i / columns + 1) * h, width: 104, height: 106)
    }

    /// Where the next file to land will sit, in stage coordinates.
    func nextSlotCenter() -> NSPoint {
        let r = slot(order.count)
        let p = body.convert(NSPoint(x: r.midX, y: r.midY + 12), to: self)
        return NSPoint(x: frame.minX + p.x, y: frame.minY + p.y)
    }

    func add(_ url: URL, animated: Bool = true) async {
        let image = await DemoThumbs.icon(for: url)
        let tile = FileTile(image: image, name: url.lastPathComponent)
        tile.frame = slot(order.count)
        order.append(url)
        tiles[url] = tile
        body.addSubview(tile)
        if animated { tile.pop() }
    }

    func center(of url: URL) -> NSPoint {
        guard let t = tiles[url] else { return NSPoint(x: frame.midX, y: frame.midY) }
        let p = body.convert(NSPoint(x: t.frame.midX, y: t.frame.midY + 12), to: self)
        return NSPoint(x: frame.minX + p.x, y: frame.minY + p.y)
    }

    func select(_ urls: [URL]) { tiles.forEach { $0.value.selected = urls.contains($0.key) } }
    func dim(_ urls: [URL], _ on: Bool) { urls.forEach { tiles[$0]?.icon.alphaValue = on ? 0.45 : 1 } }

    func dragImage(for urls: [URL]) -> NSImage {
        let icons = urls.compactMap { tiles[$0]?.icon.image }
        let size = NSSize(width: 76 + CGFloat(icons.count - 1) * 10, height: 76 + CGFloat(icons.count - 1) * 8)
        return NSImage(size: size, flipped: false) { _ in
            for (i, img) in icons.enumerated().reversed() {
                img.draw(in: NSRect(x: CGFloat(i) * 10, y: CGFloat(icons.count - 1 - i) * 8, width: 76, height: 76))
            }
            return true
        }
    }

    func appear() {
        let end = frame
        frame = end.offsetBy(dx: 0, dy: -60)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.7
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.25, 0.35, 1)
            animator().frame = end
            animator().alphaValue = 1
        }
    }

    func leave() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().frame = frame.offsetBy(dx: 0, dy: -50)
            animator().alphaValue = 0
        }
    }
}

enum DemoThumbs {
    /// Finder-style icon: a Quick Look thumbnail (photo, video frame, PDF page) or the folder icon.
    @MainActor static func icon(for url: URL) async -> NSImage {
        let fallback = NSWorkspace.shared.icon(forFile: url.path)
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return fallback }
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 76, height: 76), scale: 2, representationTypes: .thumbnail)
        return await withCheckedContinuation { c in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
                c.resume(returning: rep?.nsImage ?? fallback)
            }
        }
    }
}

/// A file on the desktop or in a window: icon over a name label, selectable like Finder.
final class FileTile: NSView {
    let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    var selected = false {
        didSet {
            label.layer?.backgroundColor = (selected ? NSColor.controlAccentColor : NSColor.clear).cgColor
            icon.layer?.backgroundColor = (selected ? NSColor(white: 1, alpha: 0.14) : NSColor.clear).cgColor
        }
    }

    init(image: NSImage, name: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 104, height: 106))
        icon.image = image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 8
        icon.frame = NSRect(x: 14, y: 26, width: 76, height: 76)
        label.stringValue = name
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        label.frame = NSRect(x: 4, y: 4, width: 96, height: 17)
        addSubview(icon)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Lands with a little bounce, like a new file appearing.
    func pop() {
        wantsLayer = true
        let bounce = CASpringAnimation(keyPath: "transform.scale")
        bounce.fromValue = 0.3
        bounce.toValue = 1
        bounce.damping = 10
        bounce.stiffness = 240
        bounce.duration = bounce.settlingDuration
        layer?.add(bounce, forKey: "pop")
    }
}

/// A slim fake menu bar so the stage reads as a Mac.
final class MenuBar: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.25).cgColor
        let menus = NSTextField(labelWithAttributedString: NSAttributedString(string: "Finder    File    Edit    View    Go", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.92)]))
        menus.frame = NSRect(x: 18, y: 6, width: 300, height: 18)
        let clock = NSTextField(labelWithString: "9:41")
        clock.font = .systemFont(ofSize: 13, weight: .semibold)
        clock.textColor = NSColor(white: 1, alpha: 0.92)
        clock.frame = NSRect(x: frame.width - 56, y: 6, width: 44, height: 18)
        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)!)
        icon.contentTintColor = .white
        icon.frame = NSRect(x: frame.width - 90, y: 6, width: 18, height: 18)
        [menus, clock, icon].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A keyboard key that lights up while held.
final class KeyCap: NSView {
    private let glyph = NSTextField(labelWithString: "")
    private let word = NSTextField(labelWithString: "")

    var down = false {
        didSet {
            guard down != oldValue else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.allowsImplicitAnimation = true
                layer?.backgroundColor = (down ? NSColor.controlAccentColor : NSColor(white: 1, alpha: 0.94)).cgColor
                layer?.setAffineTransform(down ? CGAffineTransform(translationX: 0, y: -3).scaledBy(x: 0.96, y: 0.96) : .identity)
            }
            glyph.textColor = down ? .white : NSColor(white: 0.1, alpha: 1)
            word.textColor = down ? NSColor(white: 1, alpha: 0.85) : NSColor(white: 0.3, alpha: 1)
        }
    }

    init(glyph g: String, word w: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 72, height: 58))
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.94).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        glyph.stringValue = g
        glyph.font = .systemFont(ofSize: 21, weight: .semibold)
        glyph.textColor = NSColor(white: 0.1, alpha: 1)
        glyph.frame = NSRect(x: 10, y: 28, width: 30, height: 25)
        word.stringValue = w
        word.font = .systemFont(ofSize: 11, weight: .semibold)
        word.textColor = NSColor(white: 0.3, alpha: 1)
        word.alignment = .right
        word.frame = NSRect(x: 8, y: 7, width: 56, height: 14)
        addSubview(glyph)
        addSubview(word)
        widthAnchor.constraint(equalToConstant: 72).isActive = true
        heightAnchor.constraint(equalToConstant: 58).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
}
#endif
