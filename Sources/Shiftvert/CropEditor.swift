import AppKit

/// What the person chose in the crop editor: the area to keep (image pixels, top-left origin) and the output size.
struct CropChoice {
    let rect: CGRect
    let size: CGSize
}

/// A small glass editor for the Crop tool: drag a crop box over a live preview, snap to an aspect ratio, and set the
/// output size as a percentage or exact pixels. Return saves, Esc cancels.
@MainActor final class CropEditor: NSObject {
    static var level: NSWindow.Level = .floating
    static var width: CGFloat = 640
    private(set) static var current: CropEditor?

    /// Width ÷ height; `nil` is free, `-1` keeps the photo's own shape.
    static let presets: [(title: String, ratio: CGFloat?)] = [
        ("Free", nil), ("Original", -1), ("1:1", 1), ("4:5", 4.0 / 5), ("3:2", 3.0 / 2), ("16:9", 16.0 / 9), ("9:16", 9.0 / 16),
    ]

    private let panel: EditorPanel
    private let content = NSView()
    private let canvas: CropCanvas
    private let aspects: NSSegmentedControl
    private let slider = NSSlider(value: 100, minValue: 5, maxValue: 100, target: nil, action: nil)
    private let percent = NSTextField(labelWithString: "100%")
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset", target: nil, action: nil)
    private var continuation: CheckedContinuation<CropChoice?, Never>?
    private let onSave = dialogDone  // read while the job's task opens the editor; Save runs outside it

    static func present(_ image: CGImage, name: String) async -> CropChoice? {
        let editor = CropEditor(image: image, name: name)
        current = editor
        let choice = await withCheckedContinuation { (c: CheckedContinuation<CropChoice?, Never>) in
            editor.continuation = c
            editor.show()
        }
        current = nil
        return choice
    }

    private init(image: CGImage, name: String) {
        let w = CropEditor.width, canvasHeight = ((w - 40) * 0.62).rounded(), h = canvasHeight + 196
        panel = EditorPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
        canvas = CropCanvas(image: image)
        aspects = NSSegmentedControl(labels: CropEditor.presets.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = CropEditor.level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false  // Shiftvert has no Dock icon, so a hidden editor could never come back
        let glass = makeGlass(radius: 24)
        glass.frame = NSRect(x: 0, y: 0, width: w, height: h)
        setGlassContent(glass, content)
        panel.contentView = glass

        let title = NSTextField(labelWithAttributedString: {
            let s = NSMutableAttributedString(string: "Crop  ", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: NSColor.labelColor])
            s.append(NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]))
            return s
        }())
        title.lineBreakMode = .byTruncatingMiddle
        title.frame = NSRect(x: 22, y: h - 40, width: w - 44, height: 20)

        canvas.frame = NSRect(x: 20, y: 150, width: w - 40, height: canvasHeight)
        canvas.wantsLayer = true
        canvas.layer?.cornerRadius = 12
        canvas.layer?.masksToBounds = true
        canvas.onChange = { [weak self] in self?.refreshSize() }

        aspects.target = self
        aspects.action = #selector(aspectChanged)
        aspects.selectedSegment = 0
        aspects.segmentStyle = .rounded
        aspects.controlSize = w < 560 ? .small : .regular
        aspects.sizeToFit()
        let segment = min((w - 40) / CGFloat(aspects.segmentCount), 74)
        for i in 0..<aspects.segmentCount { aspects.setWidth(segment - 2, forSegment: i) }
        aspects.sizeToFit()
        aspects.frame.origin = NSPoint(x: (w - aspects.frame.width) / 2, y: 108)

        let sizeLabel = NSTextField(labelWithString: "Size")
        sizeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        sizeLabel.frame = NSRect(x: 22, y: 66, width: 40, height: 18)
        percent.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        percent.alignment = .right
        for field in [widthField, heightField] {
            field.alignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            field.formatter = { let f = NumberFormatter(); f.allowsFloats = false; f.minimum = 1; return f }()
            field.target = self
            field.action = #selector(fieldChanged(_:))
            field.cell?.sendsActionOnEndEditing = true
        }
        let times = NSTextField(labelWithString: "×")
        let px = NSTextField(labelWithString: "px")
        px.textColor = .secondaryLabelColor
        let right = w - 22
        px.frame = NSRect(x: right - 18, y: 66, width: 20, height: 18)
        heightField.frame = NSRect(x: right - 18 - 6 - 66, y: 62, width: 66, height: 24)
        times.frame = NSRect(x: heightField.frame.minX - 16, y: 66, width: 12, height: 18)
        widthField.frame = NSRect(x: times.frame.minX - 4 - 66, y: 62, width: 66, height: 24)
        percent.frame = NSRect(x: widthField.frame.minX - 12 - 46, y: 66, width: 46, height: 18)
        slider.frame = NSRect(x: 66, y: 62, width: percent.frame.minX - 8 - 66, height: 24)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sizeChanged)

        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.frame = NSRect(x: w - 22 - 92, y: 16, width: 92, height: 32)
        cancelButton.frame = NSRect(x: saveButton.frame.minX - 8 - 92, y: 16, width: 92, height: 32)
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(reset)
        resetButton.frame = NSRect(x: 18, y: 16, width: 84, height: 32)

        [title, canvas, aspects, sizeLabel, slider, percent, widthField, times, heightField, px, resetButton, cancelButton, saveButton].forEach(content.addSubview)
        refreshSize()
    }

    private func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let v = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: (v.midX - panel.frame.width / 2).rounded(), y: (v.midY - panel.frame.height / 2).rounded()))
        }
        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
    }

    private func finish(_ choice: CropChoice?) {
        continuation?.resume(returning: choice)
        continuation = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 }) { [panel] in
            DispatchQueue.main.async { panel.orderOut(nil) }
        }
    }

    // MARK: Controls

    /// Output size ÷ crop size. Kept apart from the slider, which stops at 5 %, so exact pixels can go smaller.
    private var scale = 1.0

    private var output: CGSize {
        CGSize(width: max(1, (canvas.crop.width * scale).rounded()), height: max(1, (canvas.crop.height * scale).rounded()))
    }

    private func refreshSize() {
        let p = scale * 100
        percent.stringValue = p < 0.1 ? "<0.1%" : p < 1 ? String(format: "%.1f%%", p) : "\(Int(p.rounded()))%"
        widthField.integerValue = Int(output.width)
        heightField.integerValue = Int(output.height)
    }

    @objc private func aspectChanged() {
        let ratio = CropEditor.presets[aspects.selectedSegment].ratio
        canvas.lock(ratio.map { $0 < 0 ? canvas.imageSize.width / canvas.imageSize.height : $0 })
    }

    @objc private func sizeChanged() {
        scale = slider.doubleValue / 100
        refreshSize()
    }

    /// Typing a width or height sets the scale; the other side follows the crop's shape.
    @objc private func fieldChanged(_ field: NSTextField) {
        guard field.integerValue >= 1 else { return refreshSize() }  // an emptied field puts the size back
        let side = field === widthField ? canvas.crop.width : canvas.crop.height
        scale = min(1, max(1, Double(field.integerValue)) / Double(side))
        slider.doubleValue = max(slider.minValue, scale * 100)
        refreshSize()
    }

    @objc func save() {
        // Ends typing in a size field first, so a number entered without Return still counts.
        guard panel.makeFirstResponder(nil) else { NSSound.beep(); return }
        let c = canvas.crop, h = canvas.imageSize.height
        guard c.width >= 1, c.height >= 1 else { NSSound.beep(); return }
        onSave?()
        finish(CropChoice(rect: CGRect(x: c.minX.rounded(), y: (h - c.maxY).rounded(), width: c.width.rounded(), height: c.height.rounded()), size: output))
    }

    @objc func cancel() { finish(nil) }

    @objc private func reset() {
        aspects.selectedSegment = 0
        slider.doubleValue = 100
        scale = 1
        canvas.reset()
        refreshSize()
    }

    // MARK: Scripting (used by the product video)

    private func screen(_ p: NSPoint, in view: NSView) -> NSPoint {
        panel.convertPoint(toScreen: view.convert(p, to: nil))
    }

    func point(ofAspect i: Int) -> NSPoint {
        let w = aspects.frame.width / CGFloat(aspects.segmentCount)
        return screen(NSPoint(x: aspects.frame.minX + w * (CGFloat(i) + 0.5), y: aspects.frame.midY), in: content)
    }

    func selectAspect(_ i: Int) {
        aspects.selectedSegment = i
        aspectChanged()
    }

    private var knobInset: CGFloat { 10 }

    func point(forPercent p: Double) -> NSPoint {
        let f = slider.frame, t = (p - slider.minValue) / (slider.maxValue - slider.minValue)
        return screen(NSPoint(x: f.minX + knobInset + (f.width - knobInset * 2) * t, y: f.midY), in: content)
    }

    func percent(atScreenX x: CGFloat) -> Double {
        let left = point(forPercent: slider.minValue).x, right = point(forPercent: slider.maxValue).x
        return slider.minValue + Double((x - left) / (right - left)) * (slider.maxValue - slider.minValue)
    }

    func setPercent(_ p: Double) {
        slider.doubleValue = min(slider.maxValue, max(slider.minValue, p))
        scale = slider.doubleValue / 100
        refreshSize()
    }

    var pointOfSave: NSPoint { screen(NSPoint(x: saveButton.frame.midX, y: saveButton.frame.midY), in: content) }
}

/// A borderless panel that can still take keyboard focus (Return / Esc, typing sizes).
final class EditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The preview with a draggable crop box: corners and edges resize, inside moves; an aspect ratio can lock its shape.
final class CropCanvas: NSView {
    let imageSize: CGSize
    private let preview: CGImage
    private(set) var crop: CGRect  // image pixels, bottom-left origin
    private var ratio: CGFloat?
    var onChange: (() -> Void)?

    private enum Grab { case move, corner(Int), edge(Int) }  // corners: 0 BL, 1 BR, 2 TL, 3 TR; edges: 0 left, 1 right, 2 bottom, 3 top
    private var grab: Grab?
    private var startCrop = CGRect.zero
    private var startPoint = CGPoint.zero
    private var animation = 0

    init(image: CGImage) {
        imageSize = CGSize(width: image.width, height: image.height)
        crop = CGRect(origin: .zero, size: imageSize)
        preview = CropCanvas.downscaled(image, maxSide: 1600)
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let side = max(image.width, image.height)
        guard side > maxSide else { return image }
        let k = CGFloat(maxSide) / CGFloat(side), w = Int(CGFloat(image.width) * k), h = Int(CGFloat(image.height) * k)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    // MARK: Geometry

    private var fit: CGRect {
        let area = bounds.insetBy(dx: 10, dy: 10)
        let k = min(area.width / imageSize.width, area.height / imageSize.height)
        let size = CGSize(width: imageSize.width * k, height: imageSize.height * k)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func inView(_ r: CGRect) -> CGRect {
        let f = fit, k = f.width / imageSize.width
        return CGRect(x: f.minX + r.minX * k, y: f.minY + r.minY * k, width: r.width * k, height: r.height * k)
    }

    private func inImage(_ p: NSPoint) -> CGPoint {
        let f = fit, k = imageSize.width / f.width
        return CGPoint(x: (p.x - f.minX) * k, y: (p.y - f.minY) * k)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor(white: 0, alpha: 0.25).setFill()
        bounds.fill()
        let f = fit, c = inView(crop)
        ctx.interpolationQuality = .high
        ctx.draw(preview, in: f)
        ctx.addRect(f)
        ctx.addRect(c)
        ctx.setFillColor(NSColor(white: 0, alpha: 0.55).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.35).cgColor)
        ctx.setLineWidth(0.75)
        for i in 1...2 {
            let x = c.minX + c.width * CGFloat(i) / 3, y = c.minY + c.height * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: x, y: c.minY)); ctx.addLine(to: CGPoint(x: x, y: c.maxY))
            ctx.move(to: CGPoint(x: c.minX, y: y)); ctx.addLine(to: CGPoint(x: c.maxX, y: y))
        }
        ctx.strokePath()
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(c.insetBy(dx: 0.75, dy: 0.75))
        let l = min(22, c.width / 3, c.height / 3), i = c.insetBy(dx: 2, dy: 2)
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        for (x, y, dx, dy) in [(i.minX, i.minY, l, l), (i.maxX, i.minY, -l, l), (i.minX, i.maxY, l, -l), (i.maxX, i.maxY, -l, -l)] {
            ctx.move(to: CGPoint(x: x + dx, y: y)); ctx.addLine(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x, y: y + dy))
        }
        ctx.strokePath()
        // Short bars at the middle of each edge.
        let m = min(18, c.width / 4, c.height / 4)
        for (a, b) in [(CGPoint(x: c.midX - m / 2, y: i.minY), CGPoint(x: c.midX + m / 2, y: i.minY)),
                       (CGPoint(x: c.midX - m / 2, y: i.maxY), CGPoint(x: c.midX + m / 2, y: i.maxY)),
                       (CGPoint(x: i.minX, y: c.midY - m / 2), CGPoint(x: i.minX, y: c.midY + m / 2)),
                       (CGPoint(x: i.maxX, y: c.midY - m / 2), CGPoint(x: i.maxX, y: c.midY + m / 2))] {
            ctx.move(to: a); ctx.addLine(to: b)
        }
        ctx.strokePath()
    }

    func reset() {
        ratio = nil
        animate(to: CGRect(origin: .zero, size: imageSize))
    }

    override func resetCursorRects() {
        addCursorRect(inView(crop).insetBy(dx: 12, dy: 12), cursor: .openHand)
    }

    // MARK: Interaction

    private func hit(_ p: NSPoint) -> Grab? {
        let c = inView(crop)
        let corners = [CGPoint(x: c.minX, y: c.minY), CGPoint(x: c.maxX, y: c.minY), CGPoint(x: c.minX, y: c.maxY), CGPoint(x: c.maxX, y: c.maxY)]
        if let i = corners.firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) < 18 }) { return .corner(i) }
        let withinY = p.y > c.minY && p.y < c.maxY, withinX = p.x > c.minX && p.x < c.maxX
        if withinY && abs(p.x - c.minX) < 10 { return .edge(0) }
        if withinY && abs(p.x - c.maxX) < 10 { return .edge(1) }
        if withinX && abs(p.y - c.minY) < 10 { return .edge(2) }
        if withinX && abs(p.y - c.maxY) < 10 { return .edge(3) }
        return c.contains(p) ? .move : nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        grab = hit(p)
        startCrop = crop
        startPoint = inImage(p)
        if case .move = grab { NSCursor.closedHand.push() }
    }

    override func mouseUp(with event: NSEvent) {
        if case .move = grab { NSCursor.pop() }
        grab = nil
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grab else { return }
        let q = inImage(convert(event.locationInWindow, from: nil)), s = startCrop
        let W = imageSize.width, H = imageSize.height, minSide = min(16, W, H)  // tiny images can't fit a 16 px box
        var r = s
        switch grab {
        case .move:
            r.origin.x = min(max(0, s.minX + q.x - startPoint.x), W - s.width)
            r.origin.y = min(max(0, s.minY + q.y - startPoint.y), H - s.height)
        case .corner(let i):
            let anchor = CGPoint(x: i % 2 == 0 ? s.maxX : s.minX, y: i < 2 ? s.maxY : s.minY)
            guard let n = rect(from: anchor, to: q) else { return }
            r = n
        case .edge(let e):
            if let ratio {
                // Locked shape: the dragged side sets the size, centred on the other axis.
                if e < 2 {
                    var w = e == 0 ? s.maxX - q.x : q.x - s.minX
                    w = min(max(w, minSide), e == 0 ? s.maxX : W - s.minX, H * ratio)
                    let h = w / ratio
                    r = CGRect(x: e == 0 ? s.maxX - w : s.minX, y: min(max(0, s.midY - h / 2), H - h), width: w, height: h)
                } else {
                    var h = e == 2 ? s.maxY - q.y : q.y - s.minY
                    h = min(max(h, minSide), e == 2 ? s.maxY : H - s.minY, W / ratio)
                    let w = h * ratio
                    r = CGRect(x: min(max(0, s.midX - w / 2), W - w), y: e == 2 ? s.maxY - h : s.minY, width: w, height: h)
                }
            } else {
                switch e {
                case 0: let x = min(max(0, q.x), s.maxX - minSide); r = CGRect(x: x, y: s.minY, width: s.maxX - x, height: s.height)
                case 1: let x = max(min(W, q.x), s.minX + minSide); r.size.width = x - s.minX
                case 2: let y = min(max(0, q.y), s.maxY - minSide); r = CGRect(x: s.minX, y: y, width: s.width, height: s.maxY - y)
                default: let y = max(min(H, q.y), s.minY + minSide); r.size.height = y - s.minY
                }
            }
        }
        set(r)
    }

    /// The box between a fixed corner and the pointer, kept inside the photo and to the locked shape.
    private func rect(from a: CGPoint, to q: CGPoint) -> CGRect? {
        let W = imageSize.width, H = imageSize.height, minSide = min(16, W, H)
        let right = q.x >= a.x, up = q.y >= a.y
        var w = max(abs(q.x - a.x), minSide), h = max(abs(q.y - a.y), minSide)
        let maxW = right ? W - a.x : a.x, maxH = up ? H - a.y : a.y
        // Dragged past the photo's edge on the anchor's side: there's no room, so keep the current box.
        guard maxW >= minSide, maxH >= minSide else { return nil }
        if let ratio { if w / h > ratio { w = h * ratio } else { h = w / ratio } }
        if w > maxW { w = maxW; if let ratio { h = w / ratio } }
        if h > maxH { h = maxH; if let ratio { w = h * ratio } }
        return CGRect(x: right ? a.x : a.x - w, y: up ? a.y : a.y - h, width: w, height: h)
    }

    private func set(_ r: CGRect) {
        crop = r
        needsDisplay = true
        onChange?()
    }

    /// Locks (or frees) the shape. A locked shape snaps to the largest box of that ratio around the current centre.
    func lock(_ ratio: CGFloat?) {
        self.ratio = ratio
        guard let ratio else { return }
        let W = imageSize.width, H = imageSize.height
        let w = min(W, H * ratio), h = w / ratio
        let x = min(max(0, crop.midX - w / 2), W - w), y = min(max(0, crop.midY - h / 2), H - h)
        animate(to: CGRect(x: x, y: y, width: w, height: h))
    }

    private func animate(to target: CGRect) {
        animation += 1
        let id = animation, from = crop
        Task { @MainActor in
            for f in (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 16 : 1)...16 {
                guard id == animation else { return }
                let t = Double(f) / 16, e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                set(CGRect(x: from.minX + (target.minX - from.minX) * e, y: from.minY + (target.minY - from.minY) * e,
                           width: from.width + (target.width - from.width) * e, height: from.height + (target.height - from.height) * e))
                try? await Task.sleep(for: .milliseconds(16))
            }
            window?.invalidateCursorRects(for: self)
        }
    }
}
