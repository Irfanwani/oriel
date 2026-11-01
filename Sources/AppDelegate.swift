import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let prefs = Preferences.shared
    let manager = WindowManager.shared
    let displays = DisplayManager.shared
    let hud = HUDController()
    let overlays = OverlayController()
    let overview = OverviewController()
    let input = InputMonitor()
    let hotkeys = HotKeyManager()
    let scenes = SceneManager()

    private var statusItem: NSStatusItem!
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var permissionTimer: Timer?
    private var settingsWork: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register before the first Apple Event can arrive when the app is
        // launched by opening an oriel:// link.
        installURLEventHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.reset()
        DebugLog.write("launch: version \(Bundle.main.appVersion), debug=\(DebugLog.isEnabled)")
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHotKeys()
        setupCallbacks()
        observeWorkspace()
        observeSettings()

        overlays.update()
        checkAccessibility()
    }

    func applicationWillTerminate(_ notification: Notification) {
        prefs.saveNow()
        manager.stop()
        input.stop()
        hotkeys.unregisterAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.image = StatusIcon.image(layout: prefs.settings.layout, paused: false)
        statusItem.button?.toolTip = "Oriel"
        refreshMenu()
    }

    private func setupHotKeys() {
        hotkeys.register(settings: prefs.settings)
        hotkeys.onAction = { [weak self] action in
            self?.perform(action)
        }
    }

    private func setupCallbacks() {
        manager.onStateChange = { [weak self] in
            self?.refreshMenu()
            self?.overlays.update()
        }
        manager.onFocusChange = { [weak self] in
            self?.overlays.update()
            self?.overview.refresh()
        }
        manager.onWindowsChanged = { [weak self] in
            self?.refreshMenu()
            self?.overview.refresh()
        }
        manager.onHUD = { [weak self] title, subtitle, layout in
            self?.hud.show(title: title, subtitle: subtitle, layout: layout)
        }
        scenes.onStatus = { [weak self] title, subtitle in
            self?.hud.show(title: title, subtitle: subtitle, layout: nil, symbol: "sparkles")
        }
        overview.hud = hud
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let wake = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.displays.reload()
                self?.manager.reconcile(force: true)
            }
        }
        workspaceObservers.append(wake)
    }

    private func observeSettings() {
        NotificationCenter.default.addObserver(forName: .orielSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.settingsChanged() }
        }
        NotificationCenter.default.addObserver(forName: .orielDisplayConfigurationChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMenu()
                self?.overlays.update()
            }
        }
    }

    private func settingsChanged() {
        hotkeys.register(settings: prefs.settings)
        settingsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.manager.reconcile(force: true)
            self.overlays.update()
            self.refreshMenu()
        }
        settingsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func checkAccessibility() {
        if AX.isTrusted {
            permissionTimer?.invalidate()
            permissionTimer = nil
            manager.start()
            input.start()
            overlays.update()
            // If setup was interrupted, finish choosing a layout rather than
            // silently tiling with defaults.
            if !prefs.settings.hasCompletedOnboarding {
                showOnboarding()
                onboardingController?.markPermissionGranted()
            }
            return
        }
        showOnboarding()
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if AX.isTrusted {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.manager.start()
                    self.input.start()
                    self.overlays.update()
                    self.hud.show(title: "Oriel is ready", subtitle: "Pick a layout to finish setup", layout: self.prefs.settings.layout)
                    self.onboardingController?.granted()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func showOnboarding() {
        if onboardingController == nil {
            onboardingController = OnboardingWindowController(
                prefs: prefs,
                onGrant: {
                    AX.promptForAccess()
                },
                onOpenSettings: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                },
                onFinish: { [weak self] in
                    guard let self else { return }
                    self.onboardingController?.dismiss()
                    self.onboardingController = nil
                    self.prefs.update { $0.hasCompletedOnboarding = true }
                    self.manager.setLayout(self.prefs.settings.layout, announce: false)
                    if self.prefs.settings.openAtLogin, !LoginItemManager.setEnabled(true) {
                        self.prefs.update { $0.openAtLogin = false }
                    }
                }
            )
        }
        onboardingController?.show()
    }

    // MARK: - Menu

    private func refreshMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let display = manager.activeDisplay() ?? displays.primary
        let layout = display.map { prefs.screenSetting(for: $0).layout } ?? prefs.settings.layout
        statusItem.button?.image = StatusIcon.image(layout: layout, paused: manager.isPaused)
        statusItem.button?.toolTip = "Oriel · \(layout.title)"

        let header = NSMenuItem(title: menuTitle(), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if !AX.isTrusted {
            let grant = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
            menu.addItem(.separator())
        }

        let layoutItem = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        let layoutMenu = NSMenu()
        for (index, item) in LayoutKind.allCases.enumerated() {
            let menuItem = NSMenuItem(title: item.title, action: #selector(chooseLayout(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.rawValue
            menuItem.state = (layout == item) ? .on : .off
            menuItem.toolTip = item.subtitle
            layoutMenu.addItem(menuItem)
            if index == 0 { layoutMenu.addItem(.separator()) }
        }
        layoutMenu.addItem(.separator())
        let next = NSMenuItem(title: "Next Layout", action: #selector(nextLayoutAction), keyEquivalent: "")
        next.target = self
        next.keyEquivalent = "l"
        next.keyEquivalentModifierMask = prefs.settings.shortcutPrefix.modifierFlags
        layoutMenu.addItem(next)
        layoutItem.submenu = layoutMenu
        menu.addItem(layoutItem)

        let countItem = NSMenuItem(title: "Windows on This Screen", action: nil, keyEquivalent: "")
        let countMenu = NSMenu()
        let currentCapacity = display.map { prefs.screenSetting(for: $0).capacity } ?? prefs.settings.capacity
        for count in 1...5 {
            let menuItem = NSMenuItem(title: "Up to \(count)", action: #selector(chooseCount(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.tag = count
            menuItem.state = count == currentCapacity ? .on : .off
            if let display, count > layout.maxTiles(on: display) {
                menuItem.isEnabled = false
            }
            countMenu.addItem(menuItem)
        }
        countItem.submenu = countMenu
        menu.addItem(countItem)

        let arrangeItem = NSMenuItem(title: "Arrange", action: nil, keyEquivalent: "")
        let arrangeMenu = NSMenu()
        let arrangeHint = NSMenuItem(title: "Drag a window onto another to swap. Drag a gap to resize.",
                                     action: nil, keyEquivalent: "")
        arrangeHint.isEnabled = false
        arrangeMenu.addItem(arrangeHint)
        arrangeMenu.addItem(.separator())

        let biggerItem = NSMenuItem(title: "Make Main Window Bigger",
                                    action: #selector(makeBigger), keyEquivalent: "=")
        biggerItem.target = self
        biggerItem.keyEquivalentModifierMask = prefs.settings.shortcutPrefix.modifierFlags
        arrangeMenu.addItem(biggerItem)

        let smallerItem = NSMenuItem(title: "Make Main Window Smaller",
                                     action: #selector(makeSmaller), keyEquivalent: "-")
        smallerItem.target = self
        smallerItem.keyEquivalentModifierMask = prefs.settings.shortcutPrefix.modifierFlags
        arrangeMenu.addItem(smallerItem)

        let resetItem = NSMenuItem(title: "Reset Window Sizes",
                                   action: #selector(resetSizes), keyEquivalent: "0")
        resetItem.target = self
        resetItem.keyEquivalentModifierMask = prefs.settings.shortcutPrefix.modifierFlags
        arrangeMenu.addItem(resetItem)
        arrangeMenu.addItem(.separator())

        let swaps: [(String, Selector, String)] = [
            ("Swap with Window on the Left", #selector(swapLeftAction), "←"),
            ("Swap with Window on the Right", #selector(swapRightAction), "→"),
            ("Swap with Window Above", #selector(swapUpAction), "↑"),
            ("Swap with Window Below", #selector(swapDownAction), "↓")
        ]
        for (title, action, glyph) in swaps {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.toolTip = "\(prefs.settings.shortcutPrefix.displayGlyphs)\(glyph)"
            arrangeMenu.addItem(item)
        }
        arrangeMenu.addItem(.separator())

        let primaryItem = NSMenuItem(title: "Make Active Window Primary",
                                     action: #selector(makePrimary), keyEquivalent: "")
        primaryItem.target = self
        arrangeMenu.addItem(primaryItem)

        let floatItem = NSMenuItem(title: "Float or Tile Active Window",
                                   action: #selector(toggleFloatAction), keyEquivalent: "f")
        floatItem.target = self
        floatItem.keyEquivalentModifierMask = prefs.settings.shortcutPrefix.modifierFlags
        arrangeMenu.addItem(floatItem)

        let nextWindowItem = NSMenuItem(title: "Activate Next Window",
                                        action: #selector(nextWindowAction), keyEquivalent: "]")
        nextWindowItem.target = self
        nextWindowItem.keyEquivalentModifierMask = prefs.settings.shortcutPrefix.modifierFlags
        arrangeMenu.addItem(nextWindowItem)

        let previousWindowItem = NSMenuItem(title: "Activate Previous Window",
                                            action: #selector(previousWindowAction), keyEquivalent: "[")
        previousWindowItem.target = self
        previousWindowItem.keyEquivalentModifierMask = prefs.settings.shortcutPrefix.modifierFlags
        arrangeMenu.addItem(previousWindowItem)

        arrangeItem.submenu = arrangeMenu
        menu.addItem(arrangeItem)
        menu.addItem(.separator())

        let overviewItem = NSMenuItem(title: "Overview", action: #selector(showOverview), keyEquivalent: "")
        overviewItem.target = self
        overviewItem.keyEquivalent = " "
        overviewItem.keyEquivalentModifierMask = prefs.settings.shortcutPrefix.modifierFlags
        menu.addItem(overviewItem)

        let focus = NSMenuItem(title: manager.isFocusMode ? "Leave Focus Mode" : "Focus Mode", action: #selector(toggleFocus), keyEquivalent: "")
        focus.target = self
        menu.addItem(focus)

        let noPeek = NSMenuItem(title: manager.isNoPeek ? "Turn Off No Peek" : "No Peek", action: #selector(toggleNoPeek), keyEquivalent: "")
        noPeek.target = self
        noPeek.state = manager.isNoPeek ? .on : .off
        menu.addItem(noPeek)

        let clean = NSMenuItem(title: manager.isCleanSpace ? "Leave Clean Space" : "Clean Space", action: #selector(toggleCleanSpace), keyEquivalent: "")
        clean.target = self
        clean.state = manager.isCleanSpace ? .on : .off
        menu.addItem(clean)

        let retile = NSMenuItem(title: "Retile", action: #selector(retile), keyEquivalent: "")
        retile.target = self
        menu.addItem(retile)
        menu.addItem(.separator())

        let scenesItem = NSMenuItem(title: "Scenes", action: nil, keyEquivalent: "")
        let scenesMenu = NSMenu()
        let save = NSMenuItem(title: "Save Current Scene…", action: #selector(saveScene), keyEquivalent: "")
        save.target = self
        scenesMenu.addItem(save)
        if !prefs.settings.scenes.isEmpty {
            scenesMenu.addItem(.separator())
            for scene in prefs.settings.scenes.sorted(by: { $0.createdAt > $1.createdAt }) {
                let item = NSMenuItem(title: scene.name, action: #selector(restoreScene(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = scene.id.uuidString
                scenesMenu.addItem(item)
            }
        }
        scenesMenu.addItem(.separator())
        let manage = NSMenuItem(title: "Manage Scenes…", action: #selector(openScenesSettings), keyEquivalent: "")
        manage.target = self
        scenesMenu.addItem(manage)
        scenesItem.submenu = scenesMenu
        menu.addItem(scenesItem)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: manager.isPaused ? "Resume Tiling" : "Pause Tiling", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = manager.isPaused ? .on : .off
        menu.addItem(pause)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = prefs.settings.openAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let about = NSMenuItem(title: "About Oriel", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let diagnostics = NSMenuItem(title: "Troubleshooting…", action: #selector(showDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)

        let quit = NSMenuItem(title: "Quit Oriel", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func menuTitle() -> String {
        guard let display = manager.activeDisplay() ?? displays.primary else {
            return "Oriel"
        }
        let setting = prefs.screenSetting(for: display)
        let count = manager.windowCount(for: display)
        var title = "Oriel · \(setting.layout.title)"
        if prefs.settings.showMenuBarWindowCount, count > 0 {
            title += " · \(count) window\(count == 1 ? "" : "s")"
        }
        if manager.isPaused { title = "Oriel · Paused" }
        return title
    }

    // MARK: - Actions

    @objc private func grantAccess() {
        AX.promptForAccess()
        showOnboarding()
    }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let layout = LayoutKind(rawValue: raw) else { return }
        manager.setLayout(layout)
    }

    @objc private func chooseCount(_ sender: NSMenuItem) {
        manager.setCapacity(sender.tag)
    }

    @objc private func nextLayoutAction() {
        manager.nextLayout()
    }

    @objc private func showOverview() {
        overview.toggle()
    }

    @objc private func toggleFocus() {
        manager.toggleFocusMode()
    }

    @objc private func toggleNoPeek() {
        manager.toggleNoPeek()
    }

    @objc private func toggleCleanSpace() {
        manager.toggleCleanSpace()
    }

    @objc private func retile() {
        manager.retile()
    }

    @objc private func makeBigger() {
        manager.adjustRatio(increase: true)
    }

    @objc private func makeSmaller() {
        manager.adjustRatio(increase: false)
    }

    @objc private func resetSizes() {
        manager.resetRatio()
    }

    @objc private func swapLeftAction() {
        manager.swapActive(direction: .left)
    }

    @objc private func swapRightAction() {
        manager.swapActive(direction: .right)
    }

    @objc private func swapUpAction() {
        manager.swapActive(direction: .up)
    }

    @objc private func swapDownAction() {
        manager.swapActive(direction: .down)
    }

    @objc private func makePrimary() {
        manager.makeActivePrimary()
    }

    @objc private func toggleFloatAction() {
        manager.toggleActiveWindowFloat()
    }

    @objc private func nextWindowAction() {
        manager.activateNextWindow()
    }

    @objc private func previousWindowAction() {
        manager.activateNextWindow(backwards: true)
    }

    @objc private func togglePause() {
        manager.togglePause()
    }

    @objc private func toggleLogin() {
        let next = !prefs.settings.openAtLogin
        prefs.update { $0.openAtLogin = next }
        let ok = LoginItemManager.setEnabled(next)
        if !ok {
            hud.show(title: "Could not update login item", subtitle: "Move Oriel to Applications and try again", symbol: "exclamationmark.triangle")
            prefs.update { $0.openAtLogin = false }
        } else if next, !LoginItemManager.isEnabled {
            hud.show(title: "Approve Open at Login", subtitle: "Allow Oriel in System Settings › Login Items", symbol: "exclamationmark.triangle")
        }
    }

    @objc private func saveScene() {
        let alert = NSAlert()
        alert.messageText = "Save this arrangement"
        alert.informativeText = "Scenes remember the apps, order, and per-display layouts. Give it a name."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Deep work"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            scenes.saveCurrentScene(named: field.stringValue)
        }
    }

    @objc private func restoreScene(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let scene = prefs.settings.scenes.first(where: { $0.id == id })
        else { return }
        scenes.restore(scene)
    }

    @objc private func openScenesSettings() {
        showSettings(page: .scenes)
    }

    @objc private func showSettings() {
        showSettings(page: nil)
    }

    private func showSettings(page: SettingsPage? = nil) {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                prefs: prefs,
                manager: manager,
                displays: displays,
                scenes: scenes,
                onChange: { [weak self] in
                    self?.settingsChanged()
                }
            )
        }
        settingsController?.show(page: page)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Oriel"
        alert.informativeText = "A calmer desktop for macOS.\n\nVersion \(Bundle.main.appVersion) (\(Bundle.main.buildVersion))\n\nOpen source · MIT License\nNative AppKit + SwiftUI\n\nMade by Irfan Wani"
        alert.addButton(withTitle: "GitHub")
        alert.addButton(withTitle: "Close")
        alert.icon = Brand.icon
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/Irfanwani/oriel") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func showDiagnostics() {
        manager.reconcile(force: true)
        NSApp.activate(ignoringOtherApps: true)
        let report = manager.diagnosticsReport()
        let alert = NSAlert()
        alert.messageText = "Oriel diagnostics"
        alert.informativeText = report
        alert.addButton(withTitle: "Copy Report")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .swapLeft: manager.swapActive(direction: .left)
        case .swapRight: manager.swapActive(direction: .right)
        case .swapUp: manager.swapActive(direction: .up)
        case .swapDown: manager.swapActive(direction: .down)
        case .bigger: manager.adjustRatio(increase: true)
        case .smaller: manager.adjustRatio(increase: false)
        case .resetSize: manager.resetRatio()
        case .nextWindow: manager.activateNextWindow()
        case .previousWindow: manager.activateNextWindow(backwards: true)
        case .stackNext: manager.cycleStack()
        case .stackPrevious: manager.cycleStack(backwards: true)
        case .floatToggle: manager.toggleActiveWindowFloat()
        case .focusMode: manager.toggleFocusMode()
        case .noPeek: manager.toggleNoPeek()
        case .cleanSpace: manager.toggleCleanSpace()
        case .retile: manager.retile()
        case .nextLayout: manager.nextLayout()
        case .previousLayout: manager.previousLayout()
        case .overview: overview.toggle()
        case .count1: manager.setCapacity(1)
        case .count2: manager.setCapacity(2)
        case .count3: manager.setCapacity(3)
        case .count4: manager.setCapacity(4)
        case .count5: manager.setCapacity(5)
        }
    }

    // MARK: - URLs

    private func installURLEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string)
        else { return }
        handleURL(url)
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "oriel" else { return }
        let host = url.host ?? ""
        let path = url.pathComponents.filter { $0 != "/" }.joined(separator: "/")
        switch host {
        case "layout":
            if path == "next" { manager.nextLayout() }
            else if path == "previous" { manager.previousLayout() }
            else if let layout = LayoutKind(rawValue: path) { manager.setLayout(layout) }
        case "count":
            if let count = Int(path) { manager.setCapacity(count) }
        case "scene":
            let name = path.removingPercentEncoding ?? path
            if let scene = prefs.settings.scenes.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                scenes.restore(scene)
            } else {
                hud.show(title: "Scene not found", subtitle: name.isEmpty ? "No scene name supplied" : name,
                         symbol: "exclamationmark.triangle")
            }
        case "save-scene":
            let name = path.removingPercentEncoding ?? path
            scenes.saveCurrentScene(named: name)
        case "focus": manager.toggleFocusMode()
        case "float": manager.toggleActiveWindowFloat()
        case "no-peek": manager.toggleNoPeek()
        case "clean-space": manager.toggleCleanSpace()
        case "retile": manager.retile()
        case "pause": if !manager.isPaused { manager.togglePause() }
        case "resume": if manager.isPaused { manager.togglePause() }
        case "overview": overview.toggle()
        case "settings":
            showSettings(page: SettingsPage(rawValue: path))
        case "scenes":
            showSettings(page: .scenes)
        case "apps":
            showSettings(page: .apps)
        default:
            break
        }
    }
}
