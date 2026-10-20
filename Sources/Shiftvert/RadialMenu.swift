import AppKit

// MARK: Glass (Liquid Glass on macOS 26+, frosted blur before)

@MainActor func makeGlass(radius: CGFloat) -> NSView {
    if #available(macOS 26, *) {
        let glass = NSGlassEffectView()
        glass.cornerRadius = radius
        return glass
    }
    let blur = NSVisualEffectView()
    blur.material = .popover
    blur.state = .active
    blur.blendingMode = .behindWindow
    blur.wantsLayer = true
    blur.layer?.cornerRadius = radius
    blur.layer?.masksToBounds = true
    return blur
}

@MainActor func setGlassContent(_ glass: NSView, _ content: NSView) {
    content.frame = glass.bounds
    content.autoresizingMask = [.width, .height]
    if #available(macOS 26, *), let glass = glass as? NSGlassEffectView { glass.contentView = content } else { glass.addSubview(content) }
}

private func centered(_ c: NSPoint, _ size: CGFloat) -> NSRect {
    NSRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
}

/// Gentle overshoot, like system spring animations.
private let spring = CAMediaTimingFunction(controlPoints: 0.3, 1.25, 0.4, 1)

/// Spoken by VoiceOver (silent otherwise).
@MainActor func announce(_ text: String) {
    NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                         userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
}

@MainActor private func animate(_ duration: TimeInterval, _ curve: CAMediaTimingFunction = spring, _ changes: () -> Void) {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
        ctx.timingFunction = curve
        ctx.allowsImplicitAnimation = true
        changes()
    }
}

// MARK: Panel

final class RadialPanel: NSPanel {
    let ring = RadialView(frame: NSRect(origin: .zero, size: RadialView.size))
    private var generation = 0

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: RadialView.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = ring
    }

    override var canBecomeKey: Bool { true }

    // Only becomes key in click mode (menu bar → Convert Files…); clicking elsewhere closes it.
    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    func show(_ actions: [Action], files: [URL], at point: NSPoint) {
        generation += 1
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        var f = NSRect(x: point.x - frame.width / 2, y: point.y - frame.height / 2, width: frame.width, height: frame.height)
        if let v = screen?.visibleFrame {
            f.origin.x = min(max(f.minX, v.minX), v.maxX - f.width)
            f.origin.y = min(max(f.minY, v.minY), v.maxY - f.height)
        }
        setFrame(f, display: false)
        ring.entry = NSPoint(x: point.x - f.minX, y: point.y - f.minY)
        alphaValue = 1
        orderFrontRegardless()
        ring.load(actions, files: files)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)  // a tick on Force Touch trackpads
    }

    /// Draws the window once, unseen, so the first wheel after launch doesn't wait for it.
    func prewarm() {
        alphaValue = 0
        orderFrontRegardless()
        displayIfNeeded()
        orderOut(nil)
    }

    func dismiss() {
        guard isVisible else { return }
        let g = generation
        ring.collapse()
        Task { @MainActor in
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.animator().alphaValue = 0
            }
            if self.generation == g { self.orderOut(nil) }
        }
    }
}

// MARK: Wheel

/// The wheel: a Liquid Glass disc holding one separate tile per option. It opens on formats; tapping ⌥ during the
/// drag swaps to tools (compress, trim, zip…) and ⇧ swaps back. Any point outside the hub picks the tile in that
/// direction, so targets are generous.
final class RadialView: NSView {
    static let size = NSSize(width: 380, height: 380)
    /// Glass disc radius, and the band the tiles fill (a glass rim stays visible outside, the hub inside).
    static let discRadius: CGFloat = 150, outer: CGFloat = 139, inner: CGFloat = 56

    private var formats: [Action] = []
    private var tools: [Action] = []
    private var showingTools = false
    private(set) var actions: [Action] = []
    private(set) var files: [URL] = []
    var hovered: Int? { didSet { if hovered != oldValue { hoverChanged() } } }
    var onPick: ((Action, [URL]) -> Void)?
    var onCancel: (() -> Void)?
    /// Where the drag reached the wheel. Near a screen edge the wheel is pushed inward, so this, not the centre, is the
    /// neutral spot: nothing is picked until the pointer moves away from it.
    var entry = NSPoint.zero

    private let disc = makeGlass(radius: discRadius)
    private let face = WheelFace()
    private var picked: Int?
    private var lastFlags: NSEvent.ModifierFlags = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        disc.frame = centered(mid, Self.discRadius * 2)
        setGlassContent(disc, face)
        addSubview(disc)
        registerForDraggedTypes([.fileURL])
        face.onPress = { [weak self] in self?.pick($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    // This view handles every click and drop itself; everything inside is just the look.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var mid: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }

    func load(_ all: [Action], files: [URL]) {
        formats = all.filter(\.format)
        tools = all.filter { !$0.format }
        self.files = files
        picked = nil
        lastFlags = NSEvent.modifierFlags.intersection([.shift, .option])
        setMode(tools: formats.isEmpty)
        // The disc opens like a lens while the tiles pop out right behind it: quick, so it feels instant.
        let d = Self.discRadius * 2
        disc.frame = centered(mid, d * 0.6)
        disc.alphaValue = 0
        animate(0.28) {
            disc.animator().frame = centered(mid, d)
            disc.animator().alphaValue = 1
        }
    }

    private func setMode(tools wantTools: Bool) {
        let list = wantTools ? tools : formats
        guard !list.isEmpty else { return }
        showingTools = wantTools
        hovered = nil
        actions = list
        let other = wantTools ? formats : tools
        face.show(list, title: wantTools ? "Tools" : "Convert", hint: other.isEmpty ? nil : (wantTools ? "⇧  formats" : "⌥  tools"))
    }

    func showTools() { if !tools.isEmpty { setMode(tools: true) } }
    func showFormats() { if !formats.isEmpty { setMode(tools: false) } }

    /// A fresh press of ⌥ shows tools; a fresh press of ⇧ shows formats again.
    func followModifiers(_ flags: NSEvent.ModifierFlags) {
        let now = flags.intersection([.shift, .option])
        let pressed = now.subtracting(lastFlags)
        lastFlags = now
        if pressed.contains(.option), !showingTools, !tools.isEmpty {
            setMode(tools: true)
        } else if pressed.contains(.shift), showingTools, !formats.isEmpty {
            setMode(tools: false)
        }
    }

    func collapse() {
        if let picked { face.pulse(picked) }
        animate(0.2, CAMediaTimingFunction(name: .easeIn)) { disc.animator().frame = centered(mid, Self.discRadius * 1.7) }
    }

    private func hoverChanged() {
        face.select(hovered)
        if hovered != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    }

    func index(at p: NSPoint) -> Int? {
        let dx = p.x - mid.x, dy = p.y - mid.y, r = hypot(dx, dy)
        guard !actions.isEmpty, r > Self.inner - 4, r < Self.discRadius + 30 else { return nil }
        let step = 2 * .pi / CGFloat(actions.count)
        var a = atan2(dx, dy)  // clockwise from 12 o'clock
        if a < 0 { a += 2 * .pi }
        return Int((a + step / 2) / step) % actions.count
    }

    // MARK: Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        followModifiers(NSEvent.modifierFlags)
        let p = convert(sender.draggingLocation, from: nil)
        hovered = hypot(p.x - entry.x, p.y - entry.y) < Self.inner - 4 ? nil : index(at: p)
        return hovered == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { hovered = nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // The files the wheel opened for, which can be fewer than the drag carries (see DragWatcher.check()).
        guard let i = hovered, !files.isEmpty else { return false }
        picked = i
        let action = actions[i], urls = files
        // Let the drag session finish before anything (like the Trim dialog) blocks the main thread.
        DispatchQueue.main.async { self.onPick?(action, urls) }
        return true
    }

    // MARK: Click mode

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        followModifiers(event.modifierFlags)
        hovered = index(at: convert(event.locationInWindow, from: nil))
    }
    override func flagsChanged(with event: NSEvent) { followModifiers(event.modifierFlags) }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseDown(with event: NSEvent) {
        if let i = index(at: convert(event.locationInWindow, from: nil)), !files.isEmpty { pick(i) } else { onCancel?() }
    }

    private func pick(_ i: Int) {
        guard actions.indices.contains(i), !files.isEmpty else { return }
        picked = i
        onPick?(actions[i], files)
    }

    /// Arrows move around the wheel, Return picks, Tab swaps formats and tools, Esc closes.
    override func keyDown(with e: NSEvent) {
        let n = actions.count
        guard n > 0 else { return super.keyDown(with: e) }
        switch e.keyCode {
        case 123, 124, 125, 126:
            let i = e.keyCode == 123 || e.keyCode == 126 ? ((hovered ?? 0) - 1 + n) % n : ((hovered ?? -1) + 1) % n
            hovered = i
            announce(actions[i].title)
        case 36, 76: if let i = hovered { pick(i) }
        case 48: if showingTools { showFormats() } else { showTools() }
        case 53: onCancel?()
        default: super.keyDown(with: e)
        }
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private extension NSView {
    var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

private let centeredText: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byTruncatingTail
    return style
}()

/// Everything on the glass: the hub, the tiles, and the label pill in the middle.
final class WheelFace: NSView {
    private var tiles: [TileView] = []
    private var actions: [Action] = []
    private let hub = CAShapeLayer()
    private let pill = NSView()
    private let pillText = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private var title = ""
    private var showID = 0
    var onPress: ((Int) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(hub)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 13
        pill.addSubview(pillText)
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 9.5, weight: .medium)
        hint.textColor = .secondaryLabelColor
        addSubview(pill)
        addSubview(hint)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ actions: [Action], title: String, hint hintText: String?) {
        showID += 1
        let id = showID
        let old = tiles
        old.forEach { $0.press = nil }  // they fade out for a moment; a VoiceOver press then must not pick from the new list
        self.actions = actions
        self.title = title
        let span = 2 * .pi / CGFloat(actions.count)
        tiles = actions.enumerated().map { TileView($1, angle: CGFloat($0) * span, span: span) }
        for (i, tile) in tiles.enumerated() {
            tile.press = { [weak self] in self?.onPress?(i) }
            tile.frame = tile.restFrame(bounds, out: -16)
            tile.alphaValue = 0
            addSubview(tile, positioned: .below, relativeTo: pill)
        }
        setPill(title, emphasized: false)
        hint.stringValue = hintText ?? ""
        updateColors()

        animate(0.12, CAMediaTimingFunction(name: .easeOut)) { old.forEach { $0.animator().alphaValue = 0 } }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            old.forEach { $0.removeFromSuperview() }
        }
        for (i, tile) in tiles.enumerated() {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(10 * i))
                guard self.showID == id else { return }
                animate(0.3) {
                    tile.animator().frame = tile.restFrame(self.bounds, out: tile.highlighted ? 9 : 0)
                    tile.animator().alphaValue = 1
                }
            }
        }
    }

    func select(_ i: Int?) {
        animate(0.2) {
            for (j, tile) in tiles.enumerated() {
                tile.highlighted = j == i
                if tile.alphaValue > 0 { tile.animator().frame = tile.restFrame(bounds, out: j == i ? 9 : 0) }
            }
        }
        setPill(i.map { actions[$0].title } ?? title, emphasized: i != nil)
    }

    func pulse(_ i: Int) {
        guard tiles.indices.contains(i) else { return }
        animate(0.16, CAMediaTimingFunction(name: .easeOut)) { tiles[i].animator().frame = tiles[i].restFrame(bounds, out: 18) }
    }

    private func setPill(_ text: String, emphasized: Bool) {
        pillText.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: emphasized ? .bold : .semibold),
            .kern: 0.8,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centeredText,
        ])
        layoutCenter()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        for tile in tiles {
            tile.frame = tile.restFrame(bounds, out: tile.highlighted ? 9 : 0)
        }
        let c = CGPoint(x: bounds.midX, y: bounds.midY), r = RadialView.inner - 6
        hub.frame = bounds
        hub.path = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
        layoutCenter()
    }

    private func layoutCenter() {
        let width = min(max(pillText.attributedStringValue.size().width + 26, 70), (RadialView.inner - 10) * 2)
        let hasHint = !hint.stringValue.isEmpty
        pill.frame = NSRect(x: bounds.midX - width / 2, y: bounds.midY - 13 + (hasHint ? 7 : 0), width: width, height: 26)
        pillText.frame = NSRect(x: 6, y: 5, width: width - 12, height: 16)
        hint.frame = NSRect(x: bounds.midX - 40, y: bounds.midY - 26, width: 80, height: 13)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let dark = isDark
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hub.fillColor = NSColor(white: 1, alpha: dark ? 0.05 : 0.45).cgColor
            pill.layer?.backgroundColor = NSColor(white: 1, alpha: dark ? 0.13 : 0.95).cgColor
            pill.layer?.shadowColor = NSColor.black.cgColor
            pill.layer?.shadowOpacity = dark ? 0.3 : 0.1
            pill.layer?.shadowRadius = 3
            pill.layer?.shadowOffset = CGSize(width: 0, height: -1)
        }
        tiles.forEach { $0.updateColors() }
    }
}

/// One option: a rounded, slightly raised slice of the ring with its label. It fills with the accent colour and
/// moves outward when hovered.
final class TileView: NSView {
    let angle: CGFloat
    private let span: CGFloat
    private let drop = CALayer()
    private let body = CAGradientLayer()
    private let bodyMask = CAShapeLayer()
    private let rim = CAShapeLayer()
    private let label: CellView
    private let title: String
    var press: (() -> Void)?

    var highlighted = false {
        didSet {
            guard highlighted != oldValue else { return }
            label.highlighted = highlighted
            updateColors()
        }
    }

    init(_ action: Action, angle: CGFloat, span: CGFloat) {
        self.angle = angle
        self.span = span
        title = action.title
        label = CellView(action)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(drop)
        body.mask = bodyMask
        layer?.addSublayer(body)
        rim.fillColor = nil
        rim.lineWidth = 1
        layer?.addSublayer(rim)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityFrame() -> NSRect { NSAccessibility.screenRect(fromView: self, rect: rim.path?.boundingBox ?? bounds) }
    override func accessibilityPerformPress() -> Bool { press?(); return press != nil }

    /// Tiles are as big as the whole face and only draw their own slice, so moving one outward is a simple offset.
    func restFrame(_ bounds: NSRect, out: CGFloat) -> NSRect {
        bounds.offsetBy(dx: out * sin(angle), dy: out * cos(angle))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let c = CGPoint(x: newSize.width / 2, y: newSize.height / 2)
        let outline = Self.outline(center: c, angle: angle, span: span)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [drop, body, bodyMask, rim] { l.frame = CGRect(origin: .zero, size: newSize) }
        bodyMask.path = outline
        rim.path = outline
        drop.shadowPath = outline
        CATransaction.commit()
        let mid = (RadialView.inner + RadialView.outer) / 2
        let p = CGPoint(x: c.x + mid * sin(angle), y: c.y + mid * cos(angle))
        label.frame = NSRect(x: p.x - 38, y: p.y - 20, width: 76, height: 40)
        updateColors()
    }

    /// The band between `inner` and `outer` for this slice, pulled in to leave a gap to its neighbours,
    /// then grown back by the corner size with round joins so every corner is evenly rounded.
    static func outline(center c: CGPoint, angle a: CGFloat, span s: CGFloat) -> CGPath {
        let corner: CGFloat = 11, gap: CGFloat = 6
        let r0 = RadialView.inner + corner, r1 = RadialView.outer - corner
        let side = gap / 2 + corner
        let h1 = max(0.01, s / 2 - side / r1), h0 = max(0.01, s / 2 - side / r0)
        let theta = CGFloat.pi / 2 - a
        let core = CGMutablePath()
        core.addArc(center: c, radius: r1, startAngle: theta + h1, endAngle: theta - h1, clockwise: true)
        core.addArc(center: c, radius: r0, startAngle: theta - h0, endAngle: theta + h0, clockwise: false)
        core.closeSubpath()
        return core.union(core.copy(strokingWithWidth: corner * 2, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func updateColors() {
        let dark = isDark
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let top: NSColor, bottom: NSColor
            if highlighted {
                let accent = NSColor.controlAccentColor
                top = accent.blended(withFraction: 0.15, of: .white) ?? accent
                bottom = accent.blended(withFraction: 0.1, of: .black) ?? accent
            } else if dark {
                top = NSColor(white: 1, alpha: 0.17)
                bottom = NSColor(white: 1, alpha: 0.08)
            } else {
                top = NSColor(white: 1, alpha: 0.97)
                bottom = NSColor(white: 0.92, alpha: 0.92)
            }
            body.colors = [bottom.cgColor, top.cgColor]  // layer y points up, so this runs bottom → top
            rim.strokeColor = NSColor(white: 1, alpha: highlighted ? 0.35 : (dark ? 0.14 : 0.9)).cgColor
            drop.shadowColor = NSColor.black.cgColor
            drop.shadowOpacity = highlighted ? 0.25 : (dark ? 0.35 : 0.12)
            drop.shadowRadius = highlighted ? 6 : 4
            drop.shadowOffset = CGSize(width: 0, height: -1.5)
        }
    }
}

/// A tile's label: a format as its extension ("PNG"), or a tool as a symbol over a small caption.
final class CellView: NSView {
    private let icon = NSImageView()
    private let text = NSTextField(labelWithString: "")
    private let title: String
    private let isFormat: Bool

    var highlighted = false { didSet { style() } }

    init(_ action: Action) {
        isFormat = action.format
        title = action.title.uppercased()
        super.init(frame: .zero)
        if !isFormat {
            icon.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
            addSubview(icon)
        }
        addSubview(text)
        style()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func style() {
        let color: NSColor = highlighted ? .white : .labelColor
        icon.contentTintColor = color
        text.attributedStringValue = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: isFormat ? (title.count > 4 ? 12 : 13.5) : 8.5, weight: isFormat ? .bold : .semibold),
            .kern: isFormat ? 0.6 : 0.5,
            .foregroundColor: color,
            .paragraphStyle: centeredText,
        ])
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let midY = newSize.height / 2
        if isFormat {
            text.frame = NSRect(x: 0, y: midY - 9, width: newSize.width, height: 18)
        } else {
            icon.frame = NSRect(x: 0, y: midY - 1, width: newSize.width, height: 19)
            text.frame = NSRect(x: 0, y: midY - 15, width: newSize.width, height: 12)
        }
    }
}

/// Small glass toast near where the file was dropped: a spinner while working, a green check when done.
@MainActor final class HUD {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let glass = makeGlass(radius: 19)
    private let box = NSView()
    private let spinner = NSProgressIndicator()
    private let check = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var generation = 0

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        spinner.style = .spinning
        spinner.controlSize = .small
        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium).applying(.init(paletteColors: [.white, .systemGreen])))
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        [spinner, check, label].forEach(box.addSubview)
        setGlassContent(glass, box)
        panel.contentView = glass
    }

    func working(_ text: String, near p: NSPoint) { show(text, near: p, done: false) }
    func done(_ text: String, near p: NSPoint) { show(text, near: p, done: true) }

    private func show(_ text: String, near p: NSPoint, done: Bool) {
        label.stringValue = text
        label.sizeToFit()
        let w = min(label.frame.width, 340), size = NSSize(width: w + 54, height: 38)
        var f = NSRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height)
        if let v = (NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            f.origin.x = min(max(f.minX, v.minX + 8), v.maxX - f.width - 8)
            f.origin.y = min(max(f.minY, v.minY + 8), v.maxY - f.height - 8)
        }
        panel.setFrame(f, display: false)
        glass.frame = NSRect(origin: .zero, size: size)
        let iconFrame = NSRect(x: 14, y: (size.height - 17) / 2, width: 17, height: 17)
        spinner.frame = iconFrame
        check.frame = iconFrame
        spinner.isHidden = done
        check.isHidden = !done
        if done { spinner.stopAnimation(nil) } else { spinner.startAnimation(nil) }
        label.frame = NSRect(x: 38, y: (size.height - label.frame.height) / 2, width: w, height: label.frame.height)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        generation += 1
        guard done else { return }
        announce(text)
        let g = generation
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard g == self.generation else { return }
            await NSAnimationContext.runAnimationGroup { $0.duration = 0.3; self.panel.animator().alphaValue = 0 }
            if g == self.generation { self.panel.orderOut(nil) }
        }
    }

    func hide() {
        spinner.stopAnimation(nil)
        panel.orderOut(nil)
    }
}

// MARK: Trim dialog

var cliRange: (Double, Double)?
/// Called when a Crop or Trim window closes with a choice, so the toast can show the work that follows. Set per job.
@TaskLocal var dialogDone: (@MainActor @Sendable () -> Void)?

@MainActor func askRange(name: String, duration: Double) throws -> (Double, Double)? {
    if let r = cliRange { return r }
    let done = dialogDone
    let alert = NSAlert()
    alert.messageText = "Trim \(name)"
    alert.informativeText = "Length \(clock(duration)). Keep the part between these times (m:ss or seconds)."
    let start = NSTextField(string: "0:00"), end = NSTextField(string: clock(duration))
    for field in [start, end] { field.widthAnchor.constraint(equalToConstant: 80).isActive = true }
    let row = NSStackView(views: [NSTextField(labelWithString: "From"), start, NSTextField(labelWithString: "to"), end])
    row.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
    alert.accessoryView = row
    alert.addButton(withTitle: "Trim")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = start
    NSApp.activate()
    // A typo or a reversed range keeps the dialog open instead of making the person drag again.
    while alert.runModal() == .alertFirstButtonReturn {
        if let a = seconds(start.stringValue), let b = seconds(end.stringValue), a >= 0, a < duration, min(b, duration) > a {
            done?()
            return (a, b)
        }
        alert.informativeText = "Use times like 0:05 and 1:30, with the start before the end. Length \(clock(duration))."
        NSSound.beep()
    }
    return nil
}

func seconds(_ s: String) -> Double? {
    let parts = s.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard !parts.isEmpty, parts.count <= 3, !parts.contains(nil) else { return nil }
    return parts.reduce(0) { $0 * 60 + $1! }
}

func clock(_ t: Double) -> String {
    let s = t.isFinite ? Int(max(0, t).rounded(.up)) : 0
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}
