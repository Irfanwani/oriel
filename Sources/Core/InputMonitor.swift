import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class InputMonitor {
    private let manager = WindowManager.shared
    private let prefs = Preferences.shared

    private var monitors: [Any] = []
    private var hoverTimer: Timer?
    private var lastHoverID: String?
    private var hoverBegan: Date?
    private var didActivateHover = false

    private var downPoint: CGPoint?
    private var downWindowID: String?
    private var didDrag = false
    private var dividerDragActive = false

    func start() {
        guard AX.isTrusted, monitors.isEmpty else { return }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            Task { @MainActor [weak self] in self?.handleMouse(event) }
        }) {
            monitors.append(monitor)
        }

        let timer = Timer(timeInterval: 0.22, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        hoverTimer?.invalidate()
        hoverTimer = nil
        dividerDragActive = false
        manager.cancelDividerDrag()
        manager.endUserDrag()
        manager.isUserDragging = false
    }

    private func handleMouse(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let global = CGEvent(source: nil)?.location ?? .zero
            downPoint = global
            didDrag = false
            downWindowID = nil
            dividerDragActive = false

            // A click in the gap between tiles starts a split resize. This is
            // checked before a window drag because the handle straddles the
            // layout's primary boundary.
            if manager.beginDividerDrag(at: global) {
                dividerDragActive = true
                return
            }

            if let window = AX.window(at: global) {
                let pid = AX.pid(of: window)
                let id = "\(pid)-\(CFHash(window))"
                downWindowID = id
                manager.beginUserDrag(windowID: id)
            }
        case .leftMouseDragged:
            let global = CGEvent(source: nil)?.location ?? .zero
            if dividerDragActive {
                manager.updateDividerDrag(to: global)
                return
            }
            if let downPoint,
               hypot(global.x - downPoint.x, global.y - downPoint.y) > 12 {
                didDrag = true
            }
            if didDrag,
               let startID = downWindowID,
               manager.didDragWindowEnoughForRearrange(startID) {
                let target = manager.dropTarget(at: global, excluding: startID)
                manager.setDragTarget(target?.id)
            } else {
                manager.setDragTarget(nil)
            }
        case .leftMouseUp:
            let global = CGEvent(source: nil)?.location ?? .zero
            if dividerDragActive {
                manager.endDividerDrag()
                dividerDragActive = false
                downPoint = nil
                downWindowID = nil
                didDrag = false
                return
            }

            let startID = downWindowID
            let movedWindow = startID.map { manager.didDragWindowEnoughForRearrange($0) } ?? false
            let target: ManagedWindow?
            if didDrag, movedWindow, let startID {
                target = manager.dropTarget(at: global, excluding: startID)
            } else {
                target = nil
            }
            manager.endUserDrag()

            defer {
                downPoint = nil
                downWindowID = nil
                didDrag = false
            }

            guard didDrag else {
                manager.reconcile()
                return
            }

            if movedWindow, let startID, let target,
               manager.rearrangeWindows(startID, onto: target.id) {
                return
            }

            // A manual move should not leave the desktop untidy.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.manager.reconcile(force: true)
            }
        default:
            break
        }
    }

    private func pollHover() {
        guard prefs.settings.activateOnHover,
              !manager.isUserDragging,
              !manager.isResizingDivider,
              !manager.isPaused
        else {
            lastHoverID = nil
            hoverBegan = nil
            return
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            lastHoverID = nil
            hoverBegan = nil
            return
        }
        guard let global = CGEvent(source: nil)?.location else { return }
        guard let element = AX.window(at: global) else {
            lastHoverID = nil
            hoverBegan = nil
            didActivateHover = false
            return
        }
        let pid = AX.pid(of: element)
        let id = "\(pid)-\(CFHash(element))"
        guard manager.windows.contains(where: { $0.id == id }) else {
            lastHoverID = nil
            hoverBegan = nil
            return
        }
        if id != lastHoverID {
            lastHoverID = id
            hoverBegan = Date()
            didActivateHover = false
            return
        }
        guard !didActivateHover, let began = hoverBegan,
              Date().timeIntervalSince(began) >= prefs.settings.hoverDelay
        else { return }
        didActivateHover = true
        manager.focus(windowID: id)
    }
}
