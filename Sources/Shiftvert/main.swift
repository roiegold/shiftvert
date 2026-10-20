import AppKit
import ServiceManagement

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let panel = RadialPanel()
    let hud = HUD()
    let watcher = DragWatcher()
    var statusItem: NSStatusItem!
    var picked = false
    var shownCount = 0
    var preview: (files: [URL], hover: Int?, tools: Bool)?
    var demoOutput: URL?
    var demoWide = false
    var chime = true
    var showsToast = true
    var lastPoint = NSPoint.zero

    private var normalLaunch: Bool { demoOutput == nil && preview == nil }

    func applicationDidFinishLaunching(_ note: Notification) {
        // Only one copy runs: the one just opened (say, a new download) replaces any older one.
        var others: [NSRunningApplication] = []
        if normalLaunch, let id = Bundle.main.bundleIdentifier {
            others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != getpid() }
            others.forEach { $0.terminate() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Shiftvert")
        let menu = NSMenu()
        menu.addItem(withTitle: "Drag files, then hold ⇧ Shift", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "Convert Files…", action: #selector(openFiles), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(openUpdates), keyEquivalent: "").target = self
        if link("ShiftvertSupportURL") != nil {
            let support = menu.addItem(withTitle: "Support Shiftvert", action: #selector(openSupport), keyEquivalent: "")
            support.target = self
            support.image = NSImage(systemSymbolName: "heart", accessibilityDescription: nil)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        menu.addItem(withTitle: "Version \(version)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Shiftvert", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu

        // Hidden Edit menu, so ⌘C/⌘V/⌘A/⌘Z work in the Trim and Crop fields.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(editItem)

        panel.ring.onPick = { [weak self] action, urls in self?.perform(action, urls) }
        panel.ring.onCancel = { [weak self] in self?.panel.dismiss() }
        watcher.onShiftDrag = { [weak self] urls, point in self?.show(urls, at: point) }
        watcher.onFlags = { [weak self] in self?.panel.ring.followModifiers($0) }
        watcher.onDragEnd = { [weak self] in
            // The drop reaches our panel slightly after the mouse-up, so wait before hiding.
            guard let self else { return }
            let shown = shownCount
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                if !self.picked && self.shownCount == shown { self.panel.dismiss() }
            }
        }
        watcher.start()
        if normalLaunch { panel.prewarm() }

        #if SHIFTVERT_DEMO
        if let demoOutput {
            if #available(macOS 15, *) {
                Task { await Demo(app: self, output: demoOutput, wide: demoWide).run() }
            } else {
                fputs("The demo recorder needs macOS 15 or later.\n", stderr)
                exit(1)
            }
        }
        #endif

        if let preview, let screen = NSScreen.main?.frame {
            show(preview.files, at: NSPoint(x: screen.midX, y: screen.midY))
            if preview.tools { panel.ring.showTools() }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                self.panel.ring.hovered = preview.hover
            }
        }

        guard normalLaunch else { return }
        let defaults = UserDefaults.standard
        if Bundle.main.bundlePath.contains("/AppTranslocation/") {
            // Also when it just replaced an installed copy (an update opened straight from Downloads).
            if !defaults.bool(forKey: "moveAsked") || !others.isEmpty { defaults.set(true, forKey: "moveAsked"); DispatchQueue.main.async { self.askToMove() } }
        } else if !defaults.bool(forKey: "launched") {
            defaults.set(true, forKey: "launched")
            DispatchQueue.main.async { self.welcome() }
        } else if !others.isEmpty {
            popMenu()
        }
    }

    /// First launch: how to use Shiftvert, with Open at Login as an opt-in.
    private func welcome() {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = "Shiftvert is ready"
        a.informativeText = "It runs in the menu bar (⟳). To convert a file, start dragging it, then hold ⇧ Shift and drop it on a format. Tap ⌥ Option for tools like Compress and Trim."
        a.showsSuppressionButton = true
        a.suppressionButton?.title = "Open Shiftvert at login"
        a.runModal()
        if a.suppressionButton?.state == .on {
            try? SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        }
    }

    /// Opened where it was downloaded, macOS runs a temporary copy: Open at Login can't work and tidying Downloads removes it.
    private func askToMove() {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = "Move Shiftvert to Applications"
        a.informativeText = "You opened Shiftvert where it was downloaded, so macOS is running a temporary copy. Click below, drag Shiftvert into the Applications folder, then open it from there."
        a.addButton(withTitle: "Quit and Show Downloads")
        a.addButton(withTitle: "Not Now")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if normalLaunch { popMenu() }
        return false
    }

    /// The menu-bar icon can be hidden (notch, crowded menu bar), so opening Shiftvert shows its menu at the pointer.
    private func popMenu() {
        DispatchQueue.main.async {
            NSApp.activate()
            self.statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTitle: "Open at Login")?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func show(_ urls: [URL], at point: NSPoint) {
        picked = false
        shownCount += 1
        lastPoint = point
        panel.show(actions(for: urls), files: urls, at: point)
    }

    /// Jobs by id; true once converting (Crop and Trim count only after their window closes).
    private var jobs: [Int: Bool] = [:]
    private var lastJob = 0
    private var working: Int { jobs.values.filter { $0 }.count }

    func perform(_ action: Action, _ urls: [URL]) {
        picked = true
        watcher.used(urls)
        panel.dismiss()
        lastJob += 1
        let id = lastJob, point = lastPoint
        jobs[id] = false
        let started: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, jobs[id] != nil else { return }
            jobs[id] = true
            if showsToast { hud.working(working > 1 ? "\(working) working…" : "\(action.title)…", near: point) }
        }
        if !action.interactive { started() }
        let hook = action.interactive ? started : nil
        Task {
            do {
                let outs = try await Task.detached { try await $dialogDone.withValue(hook) { try await action.run(urls) } }.value
                let same = urls.filter { action.hideFor.contains($0.pathExtension.lowercased()) }.count
                let text = (outs.count == 1 ? outs[0].lastPathComponent : "\(outs.count) files saved") + saved(outs, from: urls)
                finished(id, text + (same > 0 ? " · \(same) already \(action.title)" : ""), near: point)
                if chime { NSSound(named: "Glass")?.play() }
            } catch let partial as PartialFailure {
                finished(id, "\(partial.outs.count) saved\(saved(partial.outs, from: urls)), \(partial.failures.count) skipped", near: point)
                alert(partial)
            } catch is CancellationError {
                finished(id, nil, near: point)
            } catch {
                finished(id, nil, near: point)
                alert(error)
            }
        }
    }

    /// " in Downloads" when results went elsewhere: files from hidden app folders are saved there.
    private func saved(_ outs: [URL], from urls: [URL]) -> String {
        guard let dir = outs.first?.deletingLastPathComponent(), dir.path != urls[0].deletingLastPathComponent().path else { return "" }
        return " in \(dir.lastPathComponent)"
    }

    /// The toast only says "done" when nothing else is still converting. A Crop or Trim cancelled in its window leaves it alone.
    private func finished(_ id: Int, _ text: String?, near point: NSPoint) {
        let shown = jobs.removeValue(forKey: id) == true
        guard showsToast, shown || text != nil else { return }
        if working > 0 { hud.working("\(working) still working…", near: point) } else if let text { hud.done(text, near: point) } else { hud.hide() }
    }

    private func alert(_ error: Error) {
        NSApp.activate()
        NSAlert(error: error).runModal()
    }

    func applicationWillTerminate(_ note: Notification) {
        // Stop helper tools mid-job and remove scratch folders, so nothing keeps running or lingers on disk.
        Running.shared.stopAll()
    }

    @objc func openFiles() {
        let open = NSOpenPanel()
        open.allowsMultipleSelection = true
        open.canChooseDirectories = true
        NSApp.activate()
        guard open.runModal() == .OK, !open.urls.isEmpty, let screen = NSScreen.main?.frame else { return }
        show(open.urls, at: NSPoint(x: screen.midX, y: screen.midY))
        panel.makeKey()
        panel.makeFirstResponder(panel.ring)
    }

    /// Links come from Info.plist (ShiftvertUpdatesURL, ShiftvertSupportURL). They open in the browser;
    /// Shiftvert itself never touches the network.
    private func link(_ key: String) -> URL? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    @objc func openUpdates() {
        NSWorkspace.shared.open(link("ShiftvertUpdatesURL") ?? URL(string: "https://github.com/roiegold/shiftvert/releases/latest")!)
    }

    @objc func openSupport() {
        if let url = link("ShiftvertSupportURL") { NSWorkspace.shared.open(url) }
    }

    @objc func toggleLogin(_ item: NSMenuItem) {
        let service = SMAppService.mainApp
        // Opened straight from Downloads, macOS runs a temporary copy whose path changes every launch.
        if service.status != .enabled, Bundle.main.bundlePath.contains("/AppTranslocation/") {
            NSApp.activate()
            let a = NSAlert()
            a.messageText = "Move Shiftvert to your Applications folder first"
            a.informativeText = "Quit Shiftvert, drag it into Applications, open it from there, then turn on Open at Login."
            a.runModal()
            return
        }
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            alert(error)
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        item.state = service.status == .enabled ? .on : .off
    }
}

// Headless mode for testing conversions: Shiftvert --list FILES | Shiftvert --run TITLE [--range 0:05-0:10] FILES
let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--list" || args.first == "--run" {
    _ = NSApplication.shared
    Task { @MainActor in
        var rest = Array(args.dropFirst())
        let title = args[0] == "--run" && !rest.isEmpty ? rest.removeFirst() : nil
        if rest.first == "--range", rest.count > 1 {
            rest.removeFirst()
            let r = rest.removeFirst().split(separator: "-").compactMap { seconds(String($0)) }
            if r.count == 2 { cliRange = (r[0], r[1]) }
        }
        let urls = rest.map { URL(fileURLWithPath: $0) }
        let list = actions(for: urls)
        guard let title else { print(list.map(\.title).joined(separator: ", ")); exit(0) }
        guard let action = list.first(where: { $0.title == title }) else {
            fputs("No action '\(title)'. Available: \(list.map(\.title).joined(separator: ", "))\n", stderr)
            exit(1)
        }
        if action.interactive, action.title == "Trim", cliRange == nil {
            fputs("Trim needs --range START-END before the files, like --range 0:05-0:10\n", stderr)
            exit(1)
        }
        do {
            for out in try await action.run(urls) { print(out.path) }
            exit(0)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    RunLoop.main.run()
}

// Unknown flags (--help, --version…) shouldn't open the app and replace the copy that's running.
if let flag = args.first, flag.hasPrefix("--"), !["--show", "--demo"].contains(flag) {
    fputs("Usage: Shiftvert --list FILES… | Shiftvert --run TITLE [--range 0:05-0:10] FILES…\n", stderr)
    exit(2)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    // Product video: Shiftvert --demo OUT.mov records a scripted demo (see Demo.swift; ./build.sh demo).
    #if SHIFTVERT_DEMO
    if args.first == "--demo", args.count > 1 {
        delegate.demoOutput = URL(fileURLWithPath: args[1])
        delegate.demoWide = args.contains("--wide")
    }
    #endif
    // Design preview: Shiftvert --show [--tools] [--hover N] FILES opens the wheel in the middle of the screen.
    if args.first == "--show" {
        var rest = Array(args.dropFirst())
        var hover: Int?
        let tools = rest.first == "--tools"
        if tools { rest.removeFirst() }
        if rest.first == "--hover", rest.count > 1 { rest.removeFirst(); hover = Int(rest.removeFirst()) }
        delegate.preview = (rest.map { URL(fileURLWithPath: $0) }, hover, tools)
    }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
