import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private let prefs = Preferences.shared
    private let displays = DisplayManager.shared

    private(set) var windows: [ManagedWindow] = []
    private(set) var displayOrder: [String: [String]] = [:]
    private(set) var activeWindowID: String?
    private var floatingWindowIDs: Set<String> = []
    private var stackTop: [String: String] = [:]
    private var knownIDs: Set<String> = []

    private var axObservers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var pendingWork: DispatchWorkItem?
    private var isReconciling = false
    private var lastSignature = ""
    private var suspended = false

    private var discoveredCount = 0
    private var runningAppCount = 0
    private var onScreenCount = 0
    private var focusDescription = "none"
    private var discoveryNotes: [String] = []

    var isPaused: Bool { suspended || !prefs.settings.isEnabled }
    private(set) var isFocusMode = false
    private(set) var isNoPeek = false
    private(set) var isCleanSpace = false
    var isUserDragging = false
    private(set) var dragSourceID: String?
    private(set) var dragTargetID: String?
    private var focusSnapshot: FocusSnapshot?

    private struct FocusSnapshot {
        var windowID: String
        var displayUUID: String
        var frames: [String: CGRect]
    }

    private struct DividerDrag {
        let displayUUID: String
        let divider: LayoutEngine.Divider
        let startPoint: CGPoint
    }

    private var dividerDrag: DividerDrag?
    private var dragStartFrame: CGRect?
    var isResizingDivider: Bool { dividerDrag != nil }

    var onStateChange: (() -> Void)?
    var onFocusChange: (() -> Void)?
    var onWindowsChanged: (() -> Void)?
    var onHUD: ((String, String, LayoutKind?) -> Void)?

    private init() {}

    func start() {
        guard AX.isTrusted else { return }
        guard timer == nil else { return }
        installWorkspaceObservers()
        observeRunningApplications()
        let t = Timer(timeInterval: 1.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        reconcile(force: true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingWork?.cancel()
        pendingWork = nil
        isUserDragging = false
        dragSourceID = nil
        dragTargetID = nil
        dragStartFrame = nil
        dividerDrag = nil
        for (_, observer) in axObservers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        axObservers.removeAll()
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }

    func refreshAccessibility() {
        if AX.isTrusted {
            start()
            reconcile(force: true)
        } else {
            stop()
        }
    }

    // MARK: - Public actions

    func retile() {
        reconcile(force: true)
        onHUD?("Tidied", "Windows are in their places", nil)
    }

    func setLayout(_ layout: LayoutKind, for display: DisplayInfo? = nil, announce: Bool = true) {
        guard let display = display ?? activeDisplay() ?? displays.primary else { return }
        prefs.setScreenLayout(layout, for: display)
        reconcile(force: true)
        if announce {
            onHUD?(layout.title, "\(windowCount(for: display)) windows on \(display.name)", layout)
        }
    }

    func setCapacity(_ capacity: Int, for display: DisplayInfo? = nil) {
        guard let display = display ?? activeDisplay() ?? displays.primary else { return }
        prefs.setScreenCapacity(capacity, for: display)
        reconcile(force: true)
        let applied = prefs.screenSetting(for: display)
        onHUD?("Up to \(applied.capacity) windows", display.name, applied.layout)
    }

    func nextLayout(for display: DisplayInfo? = nil) {
        guard let display = display ?? activeDisplay() ?? displays.primary else { return }
        let all = LayoutKind.allCases
        let current = prefs.screenSetting(for: display).layout
        let index = all.firstIndex(of: current) ?? 0
        setLayout(all[(index + 1) % all.count], for: display)
    }

    func previousLayout(for display: DisplayInfo? = nil) {
        guard let display = display ?? activeDisplay() ?? displays.primary else { return }
        let all = LayoutKind.allCases
        let current = prefs.screenSetting(for: display).layout
        let index = all.firstIndex(of: current) ?? 0
        setLayout(all[(index - 1 + all.count) % all.count], for: display)
    }

    func togglePause() {
        if !prefs.settings.isEnabled {
            prefs.update { $0.isEnabled = true }
            suspended = false
        } else {
            suspended.toggle()
        }
        if isPaused {
            setNoPeek(false)
            setCleanSpace(false)
        } else {
            reconcile(force: true)
        }
        onStateChange?()
        onHUD?(isPaused ? "Tiling paused" : "Tiling resumed", isPaused ? "Windows will stay where you put them" : "Oriel is arranging again", nil)
    }

    func toggleActiveWindowFloat() {
        guard let window = activeWindow() else { return }
        if floatingWindowIDs.contains(window.id) {
            floatingWindowIDs.remove(window.id)
            if let index = displayOrder[window.displayUUID]?.count {
                displayOrder[window.displayUUID, default: []].insert(window.id, at: index)
            }
            reconcile(force: true)
            onHUD?("Tiled", window.appName, nil)
        } else {
            floatingWindowIDs.insert(window.id)
            displayOrder[window.displayUUID]?.removeAll { $0 == window.id }
            let size = CGSize(width: min(920, window.frame.width * 1.1), height: min(720, window.frame.height * 1.1))
            let frame = CGRect(
                x: window.frame.midX - size.width / 2,
                y: window.frame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            AX.setFrame(frame, of: window.element)
            reconcile(force: true)
            onHUD?("Floating", window.appName, nil)
        }
    }

    func toggleFocusMode() {
        if isFocusMode {
            exitFocusMode()
            return
        }
        guard !isPaused, let window = activeWindow(), !window.isFloating else { return }
        var frames: [String: CGRect] = [:]
        for candidate in windows where candidate.displayUUID == window.displayUUID {
            frames[candidate.id] = candidate.frame
        }
        focusSnapshot = FocusSnapshot(windowID: window.id, displayUUID: window.displayUUID, frames: frames)
        isFocusMode = true
        if let display = displays.display(withUUID: window.displayUUID) {
            AX.setFrame(display.visibleFrame, of: window.element)
            AX.raise(window.element)
            activate(window)
        }
        onStateChange?()
        onHUD?("Focus", window.appName, nil)
    }

    private func exitFocusMode() {
        guard isFocusMode else { return }
        isFocusMode = false
        if let snapshot = focusSnapshot {
            let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
            for (id, frame) in snapshot.frames {
                if let window = byID[id] {
                    let current = AX.frame(of: window.element) ?? frame
                    if abs(current.minX - frame.minX) > 1 || abs(current.minY - frame.minY) > 1 ||
                        abs(current.width - frame.width) > 1 || abs(current.height - frame.height) > 1 {
                        AX.setFrame(frame, of: window.element)
                    }
                }
            }
            if let focusing = byID[snapshot.windowID] { activate(focusing) }
        }
        focusSnapshot = nil
        onStateChange?()
        onHUD?("Focus off", "Back to your layout", nil)
        reconcile(force: true)
    }

    func setNoPeek(_ enabled: Bool) {
        guard isNoPeek != enabled else { return }
        isNoPeek = enabled
        onStateChange?()
        onFocusChange?()
    }

    func toggleNoPeek() {
        setNoPeek(!isNoPeek)
        onHUD?(isNoPeek ? "No Peek on" : "No Peek off",
                isNoPeek ? "Only the active window stays bright" : "All windows are visible again", nil)
    }

    func setCleanSpace(_ enabled: Bool) {
        guard isCleanSpace != enabled else { return }
        isCleanSpace = enabled
        onStateChange?()
        onFocusChange?()
    }

    func toggleCleanSpace() {
        setCleanSpace(!isCleanSpace)
        onHUD?(isCleanSpace ? "Clean Space on" : "Clean Space off",
                isCleanSpace ? "A plain backdrop for sharing" : "Your desktop is back", nil)
    }

    func activateNextWindow(backwards: Bool = false) {
        guard let current = activeWindow(), let display = displays.display(withUUID: current.displayUUID) else { return }
        let list = orderedWindows(for: display)
        guard list.count > 1, let index = list.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex = (index + (backwards ? -1 : 1) + list.count) % list.count
        activate(list[nextIndex])
    }

    func cycleStack(backwards: Bool = false) {
        guard prefs.settings.stackMode == .stack else { return }
        guard let current = activeWindow(), let display = displays.display(withUUID: current.displayUUID) else { return }
        let settings = prefs.screenSetting(for: display)
        let ordered = orderedWindows(for: display)
        let capacity = effectiveCapacity(for: display)
        guard ordered.count > capacity, capacity > 0 else { return }
        let stack = Array(ordered[(capacity - 1)...])
        guard stack.count > 1 else { return }
        let topID = stackTop[display.uuid] ?? stack.last?.id
        let index = stack.firstIndex(where: { $0.id == topID }) ?? 0
        let next = stack[(index + (backwards ? -1 : 1) + stack.count) % stack.count]
        stackTop[display.uuid] = next.id
        activate(next)
        onHUD?("Stack", next.appName, settings.layout)
    }

    func swapActive(direction: SwapDirection) {
        guard let active = activeWindow(), let display = displays.display(withUUID: active.displayUUID) else { return }
        let ordered = orderedWindows(for: display)
        guard ordered.count > 1 else { return }
        guard let target = directionalNeighbor(of: active, in: ordered, direction: direction) else {
            // Move to the next display in that direction when there is no
            // window on this screen.
            moveToAdjacentDisplay(active, direction: direction)
            return
        }
        var ids = ordered.map(\.id)
        guard let a = ids.firstIndex(of: active.id), let b = ids.firstIndex(of: target.id) else { return }
        ids.swapAt(a, b)
        displayOrder[display.uuid] = ids
        reconcile(force: true)
        activate(active)
        onHUD?("Swapped", "\(active.appName) ↔ \(target.appName)", nil)
    }

    func makeActivePrimary() {
        guard let active = activeWindow() else { return }
        var ids = displayOrder[active.displayUUID] ?? []
        ids.removeAll { $0 == active.id }
        ids.insert(active.id, at: 0)
        displayOrder[active.displayUUID] = ids
        reconcile(force: true)
        activate(active)
        onHUD?("Primary", active.appName, nil)
    }

    func adjustRatio(increase: Bool) {
        guard let display = activeDisplay() ?? displays.primary else { return }
        var setting = prefs.screenSetting(for: display)
        let count = layoutInput(for: display).count
        guard count > 1 else {
            onHUD?("Single tile", "Open another tile to resize the split", setting.layout)
            return
        }
        guard !isPaused else {
            onHUD?("Tiling paused", "Resume tiling to resize windows", setting.layout)
            return
        }
        guard !isFocusMode else {
            onHUD?("Focus mode", "Leave Focus mode to resize windows", setting.layout)
            return
        }

        let input = layoutInput(for: display)
        let current = LayoutEngine.primaryShare(for: setting.layout, input: input)
        let range = LayoutEngine.primaryShareRange(for: setting.layout, input: input)
        let delta: CGFloat = increase ? 0.05 : -0.05
        let next = min(range.upperBound, max(range.lowerBound, current + delta))
        guard abs(next - current) > 0.0005 else {
            onHUD?("Main window \(Int((current * 100).rounded()))%", "\(display.name) · limit", setting.layout)
            return
        }

        setting.ratio = Double(LayoutEngine.storedRatio(forPrimaryShare: next,
                                                        layout: setting.layout,
                                                        input: input))
        prefs.update { s in s.screenOverrides[display.uuid] = setting }
        clearStaleInputStateIfNeeded()
        reconcile(force: true)
        onHUD?("Main window \(Int((next * 100).rounded()))%", display.name, setting.layout)
    }

    func resetRatio() {
        guard let display = activeDisplay() ?? displays.primary else { return }
        var setting = prefs.screenSetting(for: display)
        let count = layoutInput(for: display).count
        guard count > 1 else {
            onHUD?("Single tile", "Open another tile to resize the split", setting.layout)
            return
        }
        guard !isPaused else {
            onHUD?("Tiling paused", "Resume tiling to resize windows", setting.layout)
            return
        }
        guard !isFocusMode else {
            onHUD?("Focus mode", "Leave Focus mode to resize windows", setting.layout)
            return
        }

        setting.ratio = prefs.settings.ratio
        prefs.update { s in s.screenOverrides[display.uuid] = setting }
        let input = layoutInput(for: display)
        let share = LayoutEngine.primaryShare(for: setting.layout, input: input)
        clearStaleInputStateIfNeeded()
        reconcile(force: true)
        onHUD?("Sizes reset", "\(display.name) · \(Int((share * 100).rounded()))%", setting.layout)
    }

    func focus(windowID: String) {
        guard let window = windows.first(where: { $0.id == windowID }) else { return }
        activate(window)
    }

    // MARK: - Direct manipulation

    /// The primary split's grab area for a display. Used by the overlay to
    /// draw the handle and by InputMonitor to start a resize drag.
    func mainDivider(for display: DisplayInfo) -> LayoutEngine.Divider? {
        guard orderedWindows(for: display).count > 1 else { return nil }
        let setting = prefs.screenSetting(for: display)
        return LayoutEngine.mainDivider(for: setting.layout, input: layoutInput(for: display))
    }

    func beginDividerDrag(at point: CGPoint) -> Bool {
        guard !isPaused, !isFocusMode else { return false }
        guard let display = display(containing: point),
              let divider = mainDivider(for: display),
              divider.hitRect.contains(point)
        else { return false }

        dividerDrag = DividerDrag(displayUUID: display.uuid, divider: divider, startPoint: point)
        isUserDragging = false
        dragSourceID = nil
        dragTargetID = nil
        onFocusChange?()
        return true
    }

    func updateDividerDrag(to point: CGPoint) {
        guard let drag = dividerDrag,
              let display = displays.display(withUUID: drag.displayUUID)
        else { return }

        let delta: CGFloat
        switch drag.divider.axis {
        case .vertical: delta = point.x - drag.startPoint.x
        case .horizontal: delta = point.y - drag.startPoint.y
        }
        let share = min(drag.divider.shareRange.upperBound,
                        max(drag.divider.shareRange.lowerBound,
                            drag.divider.startShare + delta / drag.divider.availableSpan))
        let setting = prefs.screenSetting(for: display)
        let input = layoutInput(for: display)
        let current = LayoutEngine.primaryShare(for: setting.layout, input: input)
        guard abs(share - current) > 0.0005 else { return }

        let stored = LayoutEngine.storedRatio(forPrimaryShare: share,
                                              layout: setting.layout,
                                              input: input)
        prefs.setScreenRatio(Double(stored), for: display)
        applyLayout()
    }

    func endDividerDrag() {
        guard let drag = dividerDrag,
              let display = displays.display(withUUID: drag.displayUUID)
        else {
            dividerDrag = nil
            return
        }
        dividerDrag = nil
        let setting = prefs.screenSetting(for: display)
        let input = layoutInput(for: display)
        let share = LayoutEngine.primaryShare(for: setting.layout, input: input)
        reconcile(force: true)
        onHUD?("Main window \(Int((share * 100).rounded()))%", display.name, setting.layout)
    }

    func cancelDividerDrag() {
        dividerDrag = nil
    }

    func beginUserDrag(windowID: String) {
        guard let window = windows.first(where: { $0.id == windowID }) else { return }
        isUserDragging = true
        dragSourceID = window.isFloating ? nil : windowID
        dragStartFrame = AX.frame(of: window.element) ?? window.frame
        if dragTargetID != nil {
            dragTargetID = nil
            onFocusChange?()
        }
    }

    func endUserDrag() {
        isUserDragging = false
        dragSourceID = nil
        dragStartFrame = nil
        if dragTargetID != nil {
            dragTargetID = nil
            onFocusChange?()
        }
    }

    /// A drag that starts inside a window is not necessarily a window drag.
    /// Sliders, text selections and scrollbars also begin with a click on a
    /// managed window. Only rearrange when the window itself actually moved.
    func didDragWindowEnoughForRearrange(_ windowID: String) -> Bool {
        guard let window = windows.first(where: { $0.id == windowID }),
              let start = dragStartFrame,
              let current = AX.frame(of: window.element)
        else { return false }
        let moved = abs(current.minX - start.minX) > 8 ||
                    abs(current.minY - start.minY) > 8
        // Resizing from the left or top edge moves the origin while keeping
        // the opposite edge fixed. Don't treat that as a window drag.
        let leftEdgeResize = abs((current.minX - start.minX) +
                                 (current.width - start.width)) < 4
        let topEdgeResize = abs((current.minY - start.minY) +
                                (current.height - start.height)) < 4
        return moved && !leftEdgeResize && !topEdgeResize
    }

    func setDragTarget(_ id: String?) {
        guard dragSourceID != nil else {
            if dragTargetID != nil {
                dragTargetID = nil
                onFocusChange?()
            }
            return
        }
        let resolved = id.flatMap { candidate in
            windows.first { $0.id == candidate && !$0.isFloating && $0.id != (dragSourceID ?? "") }?.id
        }
        guard dragTargetID != resolved else { return }
        dragTargetID = resolved
        onFocusChange?()
    }

    /// Finds the tiled window under a drop point. The dragged window follows
    /// the cursor, so relying on an Accessibility hit test would usually
    /// return the drag source itself. Looking at the managed frames and
    /// excluding the source is more reliable.
    func dropTarget(at point: CGPoint, excluding sourceID: String) -> ManagedWindow? {
        guard let display = display(containing: point) else { return nil }
        let candidates = windows.filter {
            $0.id != sourceID && !$0.isFloating && $0.displayUUID == display.uuid
        }
        let exact = candidates.filter { $0.frame.contains(point) }
        if !exact.isEmpty {
            return exact.max { orderRank(for: $0) < orderRank(for: $1) }
        }
        let near = candidates.filter { $0.frame.insetBy(dx: -10, dy: -10).contains(point) }
        return near.min { lhs, rhs in
            distance(from: point, to: lhs.frame) < distance(from: point, to: rhs.frame)
        }
    }

    func canRearrange(_ sourceID: String, _ targetID: String) -> Bool {
        guard sourceID != targetID,
              let source = windows.first(where: { $0.id == sourceID }),
              let target = windows.first(where: { $0.id == targetID }),
              !source.isFloating, !target.isFloating,
              displayOrder[source.displayUUID]?.contains(sourceID) == true,
              displayOrder[target.displayUUID]?.contains(targetID) == true
        else { return false }
        return true
    }

    @discardableResult
    func rearrangeWindows(_ sourceID: String, onto targetID: String) -> Bool {
        guard canRearrange(sourceID, targetID),
              let source = windows.first(where: { $0.id == sourceID }),
              let target = windows.first(where: { $0.id == targetID })
        else { return false }

        let result: (String, String)
        if source.displayUUID == target.displayUUID {
            guard var ids = displayOrder[source.displayUUID],
                  let a = ids.firstIndex(of: sourceID),
                  let b = ids.firstIndex(of: targetID)
            else { return false }
            ids.swapAt(a, b)
            displayOrder[source.displayUUID] = ids
            result = ("Swapped", "\(source.appName) ↔ \(target.appName)")
        } else {
            guard let targetDisplay = displays.display(withUUID: target.displayUUID) else { return false }
            // Move the source physically onto the destination display before
            // rediscovery, otherwise reconcile would put it back where it was.
            guard AX.setFrame(target.frame, of: source.element) else { return false }
            displayOrder[source.displayUUID]?.removeAll { $0 == sourceID }
            var ids = displayOrder[target.displayUUID] ?? []
            ids.removeAll { $0 == sourceID }
            if let index = ids.firstIndex(of: targetID) {
                ids.insert(sourceID, at: index)
            } else {
                ids.append(sourceID)
            }
            displayOrder[target.displayUUID] = ids
            result = ("Moved", "\(source.appName) → \(targetDisplay.name)")
        }

        dragSourceID = nil
        dragTargetID = nil
        isUserDragging = false
        reconcile(force: true)
        if let fresh = windows.first(where: { $0.id == sourceID }) {
            activate(fresh)
        }
        onHUD?(result.0, result.1, nil)
        return true
    }

    func swapWindows(_ firstID: String, _ secondID: String) {
        rearrangeWindows(firstID, onto: secondID)
    }

    func orderedWindowsForDisplay(_ display: DisplayInfo) -> [ManagedWindow] {
        orderedWindows(for: display)
    }

    /// Every managed window on a display, including manually floated ones.
    /// Used by Overview: a floating palette should still appear on the map.
    func overviewWindows(for display: DisplayInfo) -> [ManagedWindow] {
        var result = orderedWindows(for: display)
        let known = Set(result.map(\.id))
        result.append(contentsOf: windows.filter {
            $0.displayUUID == display.uuid && $0.isFloating && !known.contains($0.id)
        })
        return result
    }

    /// Reorders current windows to match a saved scene. Missing apps are
    /// launched by SceneManager; this method only deals with the windows that
    /// currently exist.
    func applyScene(_ scene: SavedScene) {
        let currentDisplays = Set(displays.displays.map(\.uuid))
        let primaryUUID = displays.primary?.uuid
        let allByBundle = Dictionary(grouping: windows, by: \.bundleID)
        var used = Set<String>()
        var newOrder: [String: [String]] = [:]

        for display in displays.displays {
            let sceneWindows = scene.windows
                .filter { window in
                    if window.displayUUID == display.uuid { return true }
                    if !currentDisplays.contains(window.displayUUID), display.uuid == primaryUUID { return true }
                    return false
                }
                .sorted { $0.order < $1.order }

            var ids: [String] = []
            for sceneWindow in sceneWindows where !sceneWindow.floating {
                let all = (allByBundle[sceneWindow.bundleID] ?? []).filter { !used.contains($0.id) }
                // Prefer a window that already lives on the scene's display.
                // Fall back to any window only when that display disappeared.
                let sameDisplay = all.filter { $0.displayUUID == display.uuid }
                let candidate = sameDisplay.first
                    ?? (currentDisplays.contains(sceneWindow.displayUUID) ? nil : all.first)
                if let candidate {
                    ids.append(candidate.id)
                    used.insert(candidate.id)
                }
            }
            for window in windows where window.displayUUID == display.uuid && !window.isFloating && !used.contains(window.id) {
                ids.append(window.id)
                used.insert(window.id)
            }
            newOrder[display.uuid] = ids
        }

        var sceneFloats: [String: CGRect] = [:]
        for sceneWindow in scene.windows where sceneWindow.floating {
            let all = (allByBundle[sceneWindow.bundleID] ?? []).filter { !used.contains($0.id) }
            let sameDisplay = all.filter { $0.displayUUID == sceneWindow.displayUUID }
            let candidate = sameDisplay.first
                ?? (currentDisplays.contains(sceneWindow.displayUUID) ? nil : all.first)
            if let candidate {
                if let frame = sceneWindow.frame { sceneFloats[candidate.id] = frame }
                used.insert(candidate.id)
            }
        }
        // Restore the scene's floating set exactly. Otherwise a window that was
        // floating before restoring would silently stay out of the layout.
        floatingWindowIDs = Set(sceneFloats.keys)
        displayOrder = newOrder.filter { !$0.value.isEmpty }
        reconcile(force: true)
        for (id, frame) in sceneFloats {
            guard let window = windows.first(where: { $0.id == id }) else { continue }
            AX.setFrame(frame, of: window.element)
            if let index = windows.firstIndex(where: { $0.id == id }) {
                windows[index].frame = frame
            }
        }
        onFocusChange?()
    }

    /// True when every window a scene expects has a live match. Used to stop
    /// the restore retry loop as soon as app windows have arrived.
    func sceneIsCovered(_ scene: SavedScene) -> Bool {
        let needed = Dictionary(grouping: scene.windows, by: \.bundleID).mapValues(\.count)
        guard !needed.isEmpty else { return true }
        let available = Dictionary(grouping: windows, by: \.bundleID).mapValues(\.count)
        return needed.allSatisfy { available[$0.key, default: 0] >= $0.value }
    }

    func activeWindow() -> ManagedWindow? {
        guard let id = activeWindowID, let window = windows.first(where: { $0.id == id }) else { return nil }
        // A menu bar or settings window can leave the previously active window
        // remembered while another app owns the foreground. Don't let a global
        // shortcut move a window the user can't see. Oriel itself is allowed so
        // menu commands still target the last app window.
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           front != getpid(), front != window.pid {
            return nil
        }
        return window
    }

    func activeDisplay() -> DisplayInfo? {
        if let window = activeWindow(), let display = displays.display(withUUID: window.displayUUID) {
            return display
        }
        if let screen = NSScreen.main, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return displays.display(withID: CGDirectDisplayID(number.uint32Value))
        }
        return displays.primary
    }

    func windowCount(for display: DisplayInfo) -> Int {
        orderedWindows(for: display).count
    }

    func allDisplays() -> [DisplayInfo] { displays.displays }

    func diagnosticsReport() -> String {
        var lines: [String] = []
        lines.append("Oriel \(Bundle.main.appVersion) (\(Bundle.main.buildVersion))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Accessibility: \(AX.isTrusted ? "granted" : "not granted")")
        lines.append("Tiling: \(isPaused ? "paused" : "active")")
        lines.append("Focus: \(focusDescription)")
        lines.append("Running apps: \(runningAppCount)")
        lines.append("On-screen windows: \(onScreenCount)")
        lines.append("Managed windows: \(discoveredCount)")
        lines.append("Focus mode: \(isFocusMode ? "on" : "off")")
        lines.append("No Peek: \(isNoPeek ? "on" : "off")")
        lines.append("Clean Space: \(isCleanSpace ? "on" : "off")")
        lines.append("Stack mode: \(prefs.settings.stackMode.title)")
        for display in displays.displays {
            let setting = prefs.screenSetting(for: display)
            let count = overviewWindows(for: display).count
            lines.append("Display: \(display.name) · \(Int(display.visibleFrame.width))×\(Int(display.visibleFrame.height)) · \(setting.layout.title) · \(effectiveCapacity(for: display)) · \(count) windows")
        }
        if !discoveryNotes.isEmpty {
            lines.append("Notes: \(discoveryNotes.prefix(8).joined(separator: "; "))")
        }
        lines.append("Config: \(prefs.configURL.path)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Reconciliation

    func reconcile(force: Bool = false) {
        clearStaleInputStateIfNeeded()
        guard AX.isTrusted, !isReconciling, !isUserDragging else {
            if DebugLog.isEnabled, !AX.isTrusted || isUserDragging {
                DebugLog.write("reconcile skipped trusted=\(AX.isTrusted) dragging=\(isUserDragging) reconciling=\(isReconciling)")
            }
            return
        }
        isReconciling = true
        defer { isReconciling = false }

        discoveryNotes.removeAll(keepingCapacity: true)
        displays.reload()
        let onScreen = ScreenWindowIndex.current(excluding: getpid())
        onScreenCount = onScreen.count
        let focusedElement = AX.focusedWindow()
        let focusedID = focusedElement.map { identifier(for: $0, pid: AX.pid(of: $0)) }
        let activePID = AX.focusedApplicationPID()
        let myPID = getpid()
        focusDescription = focusedID ?? "none"
        var appCount = 0

        var discovered: [ManagedWindow] = []
        var discoveredIDs = Set<String>()

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  !app.isTerminated,
                  app.processIdentifier != myPID
            else { continue }
            appCount += 1
            let pid = app.processIdentifier
            let bundleID = app.bundleIdentifier ?? ""
            if bundleID.isEmpty {
                discoveryNotes.append("\(app.localizedName ?? "?") has no bundle id")
                continue
            }
            if prefs.settings.excludedBundleIDs.contains(bundleID) {
                discoveryNotes.append("skip excluded \(bundleID)")
                continue
            }

            let element = AX.appElement(pid: pid)
            if AX.bool(element, kAXHiddenAttribute as String) == true {
                discoveryNotes.append("skip hidden \(bundleID)")
                continue
            }

            let axWindows = AX.windowList(pid: pid)
            if axWindows.isEmpty { discoveryNotes.append("\(bundleID): no AX windows") }
            for axWindow in axWindows {
                if AX.bool(axWindow, kAXMinimizedAttribute as String) == true {
                    discoveryNotes.append("\(bundleID): minimized")
                    continue
                }
                guard AX.isStandardWindow(axWindow) else {
                    discoveryNotes.append("\(bundleID): not standard")
                    continue
                }
                if AX.bool(axWindow, "AXFullScreen") == true {
                    discoveryNotes.append("\(bundleID): full screen")
                    continue
                }
                guard let frame = AX.frame(of: axWindow), frame.width >= 180, frame.height >= 100 else {
                    discoveryNotes.append("\(bundleID): tiny or unreadable frame")
                    continue
                }

                let windowID = identifier(for: axWindow, pid: pid)
                let isFocused = focusedElement != nil && (windowID == focusedID || pid == activePID && AX.bool(axWindow, kAXFocusedAttribute as String) == true)
                let onScreenWindow = OnScreenWindow(pid: pid, bounds: frame)
                let visible = ScreenWindowIndex.contains(onScreenWindow, in: onScreen)
                if !visible && !isFocused {
                    discoveryNotes.append("\(bundleID): off-screen \(Int(frame.width))×\(Int(frame.height)) @ \(Int(frame.minX)),\(Int(frame.minY))")
                    continue
                }

                let title = AX.title(of: axWindow)
                if let rule = prefs.rule(for: bundleID, title: title), rule.mode == .float {
                    discoveryNotes.append("\(bundleID): app rule floats window")
                    continue
                }

                guard let display = displays.display(containing: frame) else {
                    discoveryNotes.append("\(bundleID): frame is not on a known display")
                    continue
                }
                let isFloating = floatingWindowIDs.contains(windowID)
                discovered.append(ManagedWindow(
                    id: windowID,
                    element: axWindow,
                    pid: pid,
                    bundleID: bundleID,
                    appName: app.localizedName ?? bundleID,
                    title: title,
                    frame: frame,
                    displayUUID: display.uuid,
                    isFloating: isFloating,
                    order: 0,
                    icon: app.icon
                ))
                discoveredIDs.insert(windowID)
            }
        }
        runningAppCount = appCount
        discoveredCount = discovered.count

        // Keep stable per-display order. New windows are appended.
        var newOrder: [String: [String]] = [:]
        for display in displays.displays {
            let idsOnDisplay = discovered.filter { $0.displayUUID == display.uuid }.map(\.id)
            var ordered = (displayOrder[display.uuid] ?? []).filter { idsOnDisplay.contains($0) }
            for id in idsOnDisplay where !ordered.contains(id) {
                ordered.append(id)
            }
            newOrder[display.uuid] = ordered
        }

        // Drop remembered state for windows that are gone.
        floatingWindowIDs.formIntersection(discoveredIDs)
        for (displayUUID, top) in stackTop where !discoveredIDs.contains(top) {
            stackTop.removeValue(forKey: displayUUID)
        }

        let previousKnown = knownIDs
        knownIDs = discoveredIDs
        let newIDs = discoveredIDs.subtracting(previousKnown)

        windows = discovered
        displayOrder = newOrder

        // Keep the active window current even when focus moves without a
        // window-list change.
        if let focusedID, discoveredIDs.contains(focusedID) {
            activeWindowID = focusedID
        } else if let current = activeWindowID, discoveredIDs.contains(current) {
            // keep
        } else {
            activeWindowID = orderedWindowsForAllDisplays().first?.id
        }

        // New windows beyond capacity become the top of their stack.
        for display in displays.displays {
            let ordered = orderedWindows(for: display)
            let capacity = effectiveCapacity(for: display)
            if ordered.count > capacity, capacity > 0 {
                let stack = Array(ordered[(capacity - 1)...])
                if let new = stack.first(where: { newIDs.contains($0.id) }) {
                    stackTop[display.uuid] = new.id
                } else if stackTop[display.uuid] == nil {
                    stackTop[display.uuid] = stack.last?.id
                }
            }
        }

        if let fid = focusedID, let display = displays.display(containing: windows.first(where: { $0.id == fid })?.frame ?? .zero) {
            let ordered = orderedWindows(for: display)
            let capacity = effectiveCapacity(for: display)
            if ordered.count > capacity, capacity > 0,
               ordered[(capacity - 1)...].contains(where: { $0.id == fid }) {
                stackTop[display.uuid] = fid
            }
        }

        if isFocusMode, let snapshot = focusSnapshot, !discoveredIDs.contains(snapshot.windowID) {
            isFocusMode = false
            focusSnapshot = nil
            onStateChange?()
        }

        let signature = makeSignature()
        if force || signature != lastSignature {
            lastSignature = signature
            if !isPaused && !isFocusMode {
                applyLayout()
            }
        } else {
            onFocusChange?()
        }

        onWindowsChanged?()
        onStateChange?()
        if !isPaused && !isFocusMode {
            // Borders and overlays should follow focus even when the layout did
            // not change.
            onFocusChange?()
        }

        if DebugLog.isEnabled {
            DebugLog.write("reconcile: apps=\(runningAppCount) onScreen=\(onScreenCount) managed=\(discovered.count) displayCount=\(displays.displays.count) focus=\(focusDescription) force=\(force)")
            if force || lastSignature.isEmpty {
                DebugLog.write("notes: \(discoveryNotes.joined(separator: " | "))")
            }
        }
    }

    private func applyLayout() {
        guard !isPaused, !isFocusMode else { return }
        for display in displays.displays {
            let ordered = orderedWindows(for: display)
            guard !ordered.isEmpty else { continue }
            let screenSettings = prefs.screenSetting(for: display)
            let capacity = effectiveCapacity(for: display)
            let tileCount = min(capacity, ordered.count)
            guard tileCount > 0 else { continue }
            let input = layoutInput(for: display)
            let frames = LayoutEngine.frames(for: screenSettings.layout, input: input)
            guard !frames.isEmpty else { continue }

            for (index, window) in ordered.enumerated() where index < capacity {
                let tileIndex = min(index, frames.count - 1)
                move(window, to: frames[tileIndex])
            }

            let overflow = Array(ordered.dropFirst(capacity))
            if !overflow.isEmpty {
                if prefs.settings.stackMode == .stack {
                    let target = frames[frames.count - 1]
                    for window in overflow {
                        move(window, to: target)
                    }
                    let topID = stackTop[display.uuid] ?? overflow.last?.id
                    if let topID, let top = ordered.first(where: { $0.id == topID }) {
                        AX.raise(top.element)
                        stackTop[display.uuid] = topID
                    }
                } else {
                    // Float overflow windows over the layout instead of hiding
                    // them in the last tile. They rejoin the grid automatically
                    // when the capacity grows.
                    for (offset, window) in overflow.enumerated() {
                        move(window, to: floatingOverflowFrame(for: display, offset: offset))
                    }
                    if let active = activeWindow(), overflow.contains(where: { $0.id == active.id }) {
                        AX.raise(active.element)
                    }
                }
            }
        }
        onFocusChange?()
    }

    private func move(_ window: ManagedWindow, to target: CGRect) {
        guard window.frame.width >= 1, window.frame.height >= 1 else { return }
        var actual = window.frame
        if !approximatelyEqual(actual, target) {
            _ = AX.setFrame(target, of: window.element)
            actual = AX.frame(of: window.element) ?? target
        }
        // Write the actual frame back for immediate overlay use. Apps may
        // enforce minimum sizes; the border should follow what really happened.
        if let index = windows.firstIndex(where: { $0.id == window.id }) {
            windows[index].frame = actual
        }
    }

    private func floatingOverflowFrame(for display: DisplayInfo, offset: Int) -> CGRect {
        let bounds = display.visibleFrame
        let allowed = bounds.insetBy(dx: 8, dy: 8)
        guard allowed.width > 40, allowed.height > 40 else { return bounds }
        let width = min(900, max(360, allowed.width * 0.72))
        let height = min(720, max(300, allowed.height * 0.72))
        let cascade = CGFloat(offset % 7) * 24
        let x = min(max(allowed.minX, allowed.midX - width / 2 + cascade), allowed.maxX - width)
        let y = min(max(allowed.minY, allowed.midY - height / 2 + cascade), allowed.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func makeSignature() -> String {
        var pieces: [String] = []
        for display in displays.displays {
            let screen = prefs.screenSetting(for: display)
            pieces.append("D:\(display.uuid):\(Int(display.frame.minX)):\(Int(display.frame.minY)):\(Int(display.frame.width)):\(Int(display.frame.height)):\(Int(display.visibleFrame.minX)):\(Int(display.visibleFrame.minY)):\(Int(display.visibleFrame.width)):\(Int(display.visibleFrame.height)):\(screen.layout.rawValue):\(effectiveCapacity(for: display)):\(String(format: "%.3f", screen.ratio))")
        }
        for display in displays.displays {
            for window in orderedWindows(for: display) {
                pieces.append("W:\(window.id):\(window.displayUUID):\(Int(window.frame.minX.rounded())):\(Int(window.frame.minY.rounded())):\(Int(window.frame.width.rounded())):\(Int(window.frame.height.rounded()))")
            }
        }
        pieces.append("G:\(prefs.settings.gap)")
        pieces.append("S:\(prefs.settings.stackMode.rawValue)")
        return pieces.joined(separator: "|")
    }

    private func orderedWindows(for display: DisplayInfo) -> [ManagedWindow] {
        let ids = displayOrder[display.uuid] ?? []
        let map = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        return ids.compactMap { map[$0] }.filter { !$0.isFloating && $0.displayUUID == display.uuid }
    }

    private func orderedWindowsForAllDisplays() -> [ManagedWindow] {
        displays.displays.flatMap { orderedWindows(for: $0) }
    }

    private func effectiveCapacity(for display: DisplayInfo) -> Int {
        let setting = prefs.screenSetting(for: display)
        let requested = max(1, min(5, setting.capacity))
        return min(requested, setting.layout.maxTiles(on: display))
    }

    private func layoutInput(for display: DisplayInfo) -> LayoutEngine.Input {
        let setting = prefs.screenSetting(for: display)
        let tileCount = max(1, min(effectiveCapacity(for: display),
                                   max(1, orderedWindows(for: display).count)))
        return LayoutEngine.Input(
            bounds: display.visibleFrame,
            count: tileCount,
            ratio: CGFloat(setting.ratio),
            gap: CGFloat(prefs.settings.gap),
            isUltrawide: display.isUltrawide,
            isVertical: display.isVertical
        )
    }

    private func display(containing point: CGPoint) -> DisplayInfo? {
        if let display = displays.displays.first(where: { $0.frame.contains(point) }) {
            return display
        }
        return displays.display(containing: CGRect(x: point.x, y: point.y, width: 1, height: 1))
    }

    private func orderRank(for window: ManagedWindow) -> Int {
        displayOrder[window.displayUUID]?.firstIndex(of: window.id) ?? -1
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
        let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private func clearStaleInputStateIfNeeded() {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let hadDivider = dividerDrag != nil
        let hadDrag = dragSourceID != nil || dragTargetID != nil
        if hadDivider {
            dividerDrag = nil
        }
        if isUserDragging {
            isUserDragging = false
        }
        if hadDrag {
            dragSourceID = nil
            dragTargetID = nil
            dragStartFrame = nil
        }
        if hadDivider || hadDrag {
            onFocusChange?()
        }
    }

    private func directionalNeighbor(of window: ManagedWindow, in list: [ManagedWindow], direction: SwapDirection) -> ManagedWindow? {
        let origin = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let candidates = list.filter { $0.id != window.id }
        var best: (ManagedWindow, CGFloat)?
        for candidate in candidates {
            let point = CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)
            let dx = point.x - origin.x
            let dy = point.y - origin.y
            let isAhead: Bool
            switch direction {
            case .left: isAhead = dx < -20
            case .right: isAhead = dx > 20
            case .up: isAhead = dy < -20
            case .down: isAhead = dy > 20
            }
            guard isAhead else { continue }
            let distance: CGFloat
            switch direction {
            case .left, .right: distance = abs(dx) + abs(dy) * 0.6
            case .up, .down: distance = abs(dy) + abs(dx) * 0.6
            }
            if best == nil || distance < best!.1 { best = (candidate, distance) }
        }
        return best?.0
    }

    private func moveToAdjacentDisplay(_ window: ManagedWindow, direction: SwapDirection) {
        guard let current = displays.display(withUUID: window.displayUUID) else { return }
        let candidates = displays.displays.filter { candidate in
            switch direction {
            case .left: return candidate.frame.maxX <= current.frame.minX + 1
            case .right: return candidate.frame.minX >= current.frame.maxX - 1
            case .up: return candidate.frame.maxY <= current.frame.minY + 1
            case .down: return candidate.frame.minY >= current.frame.maxY - 1
            }
        }
        guard let destination = candidates.min(by: {
            abs($0.frame.midX - current.frame.midX) + abs($0.frame.midY - current.frame.midY) <
            abs($1.frame.midX - current.frame.midX) + abs($1.frame.midY - current.frame.midY)
        }) else { return }
        // Move the frame across the display boundary first. Discovery assigns
        // windows to a display by frame, so changing only the order would put
        // the window straight back where it started.
        let width = min(window.frame.width, destination.visibleFrame.width - 16)
        let height = min(window.frame.height, destination.visibleFrame.height - 16)
        let target = CGRect(x: destination.visibleFrame.midX - width / 2,
                            y: destination.visibleFrame.midY - height / 2,
                            width: max(180, width),
                            height: max(100, height))
        guard AX.setFrame(target, of: window.element) else { return }
        displayOrder[current.uuid]?.removeAll { $0 == window.id }
        displayOrder[destination.uuid, default: []].append(window.id)
        isUserDragging = false
        reconcile(force: true)
        if let fresh = windows.first(where: { $0.id == window.id }) {
            activate(fresh)
        }
        onHUD?("Moved", "\(window.appName) → \(destination.name)", nil)
    }

    private func activate(_ window: ManagedWindow) {
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [.activateAllWindows])
        AX.raise(window.element)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        activeWindowID = window.id
        if let display = displays.display(withUUID: window.displayUUID) {
            let ordered = orderedWindows(for: display)
            let capacity = effectiveCapacity(for: display)
            if ordered.count > capacity, capacity > 0,
               ordered[(capacity - 1)...].contains(where: { $0.id == window.id }) {
                stackTop[display.uuid] = window.id
            }
        }
        onFocusChange?()
        onStateChange?()
    }

    private func identifier(for element: AXUIElement, pid: pid_t) -> String {
        "\(pid)-\(CFHash(element))"
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 1.25 &&
        abs(lhs.minY - rhs.minY) < 1.25 &&
        abs(lhs.width - rhs.width) < 1.25 &&
        abs(lhs.height - rhs.height) < 1.25
    }

    // MARK: - Accessibility notifications

    private func observeRunningApplications() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(pid: app.processIdentifier)
        }
    }

    private func observe(pid: pid_t) {
        guard pid != getpid(), axObservers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, userData in
            guard let userData else { return }
            let manager = Unmanaged<WindowManager>.fromOpaque(userData).takeUnretainedValue()
            let name = notification as String
            Task { @MainActor in
                manager.handleAXNotification(name)
            }
        }
        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let observer else { return }
        let app = AX.appElement(pid: pid)
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let notifications: [String] = [
            kAXWindowCreatedNotification as String,
            kAXUIElementDestroyedNotification as String,
            kAXWindowMiniaturizedNotification as String,
            kAXWindowDeminiaturizedNotification as String,
            kAXFocusedWindowChangedNotification as String,
            kAXApplicationHiddenNotification as String,
            kAXApplicationShownNotification as String
        ]
        for name in notifications {
            AXObserverAddNotification(observer, app, name as CFString, userData)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObservers[pid] = observer
    }

    private func handleAXNotification(_ name: String) {
        switch name {
        case "AXFocusedWindowChanged":
            updateFocusFromSystem()
        case "AXWindowCreated":
            scheduleReconcile(after: 0.18)
        case "AXUIElementDestroyed", "AXWindowMiniaturized", "AXWindowDeminiaturized",
             "AXApplicationHidden", "AXApplicationShown":
            scheduleReconcile(after: 0.08)
        default:
            break
        }
    }

    private func updateFocusFromSystem() {
        guard let focused = AX.focusedWindow() else { return }
        let id = identifier(for: focused, pid: AX.pid(of: focused))
        guard windows.contains(where: { $0.id == id }) else { return }
        activeWindowID = id
        if let window = windows.first(where: { $0.id == id }), let display = displays.display(withUUID: window.displayUUID) {
            let ordered = orderedWindows(for: display)
            let capacity = effectiveCapacity(for: display)
            if ordered.count > capacity, capacity > 0,
               ordered[(capacity - 1)...].contains(where: { $0.id == id }) {
                stackTop[display.uuid] = id
            }
        }
        onFocusChange?()
        onStateChange?()
    }

    private func scheduleReconcile(after delay: TimeInterval) {
        pendingWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
        pendingWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Workspace / displays

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let launch = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.observe(pid: app.processIdentifier)
                self?.scheduleReconcile(after: 0.35)
            }
        }
        let terminate = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.axObservers.removeValue(forKey: app.processIdentifier)
                self?.scheduleReconcile(after: 0.1)
            }
        }
        let activate = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateFocusFromSystem() }
        }
        let hide = center.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleReconcile(after: 0.15) }
        }
        let unhide = center.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleReconcile(after: 0.15) }
        }
        let space = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleReconcile(after: 0.35) }
        }
        let session = center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.displays.reload()
                self?.reconcile(force: true)
            }
        }
        let screens = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.displays.reload()
                self?.reconcile(force: true)
                NotificationCenter.default.post(name: .orielDisplayConfigurationChanged, object: nil)
            }
        }
        workspaceObservers = [launch, terminate, activate, hide, unhide, space, session, screens]
    }
}

enum SwapDirection: String, CaseIterable {
    case left, right, up, down
}
