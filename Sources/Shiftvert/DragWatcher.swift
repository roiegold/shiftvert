import AppKit
import os

private let log = Logger(subsystem: "io.github.roiegold.shiftvert", category: "drag")

/// Watches system-wide mouse drags and fires when files are dragged while Shift is held.
/// Mouse events need no Accessibility permission; the drag pasteboard is only read while Shift is down.
@MainActor final class DragWatcher {
    var onShiftDrag: (([URL], NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    /// ⇧/⌥ while the wheel is up, before the pointer moves over it (the drag only reports keys once it has).
    var onFlags: ((NSEvent.ModifierFlags) -> Void)?

    private let board = NSPasteboard(name: .drag)
    /// The drag pasteboard's count when the last drag ended. A drag that changes it is dragging something; one that
    /// doesn't is a selection or a window move. (Taking it at mouse-down races fast drags: the source app can start its
    /// drag before our copy of the mouse-down arrives.)
    private var settled = 0
    private var shown = false
    private var timer: Timer?
    private var lastMove = ContinuousClock.now
    /// The button was seen down by polling. Three-finger drag may never report it, so only then is "up" trusted.
    private var sawDown = false
    /// Shift was already down when the button went down, and the files the wheel last converted (see `check()`).
    private var shiftAtDown = false
    private var lastUsed: (urls: Set<URL>, at: ContinuousClock.Instant)?
    private var monitors: [Any] = []

    func used(_ urls: [URL]) { lastUsed = (Set(urls.map(\.standardizedFileURL)), .now) }

    func start() {
        settled = board.changeCount
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in self?.shiftAtDown = e.modifierFlags.contains(.shift) },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.dragged() },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.ended() },
        ].compactMap { $0 }
    }

    private func dragged() {
        lastMove = .now
        if timer == nil {
            // Shift often goes down while the pointer rests, which sends no events, so look ~60 times a second until the
            // button is released. Nothing runs between drags; .common keeps it going while one of our dialogs is open.
            let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
            t.tolerance = 0.004
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        check()
    }

    private func check() {
        // A missed mouse-up: only asked once the pointer has rested, since drag events already prove the button is down.
        if ContinuousClock.now - lastMove > .milliseconds(100) {
            if NSEvent.pressedMouseButtons & 1 != 0 { sawDown = true } else if sawDown || ContinuousClock.now - lastMove > .seconds(30) { return ended() }
        }
        let flags = NSEvent.modifierFlags
        if shown { onFlags?(flags); return }
        guard flags.contains(.shift), board.changeCount != settled, board.availableType(from: [.fileURL]) != nil,
              var urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return }  // not a file drag, or the files aren't written yet: look again next tick
        // Shift held while clicking the next file makes Finder add it to the selection, so the file just converted
        // comes along too. Leave that one out.
        if shiftAtDown, urls.count > 1, let last = lastUsed, ContinuousClock.now - last.at < .seconds(20) {
            let fresh = urls.filter { !last.urls.contains($0.standardizedFileURL) }
            if !fresh.isEmpty { urls = fresh }
        }
        shown = true
        log.debug("shift-drag with \(urls.count) file(s)")
        onShiftDrag?(urls, NSEvent.mouseLocation)
    }

    private func ended() {
        timer?.invalidate()
        timer = nil
        sawDown = false
        settled = board.changeCount
        if shown {
            shown = false
            onDragEnd?()
        }
    }
}
