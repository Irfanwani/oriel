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

    func start() {
        guard AX.isTrusted, monitors.isEmpty else { return }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            Task { @MainActor in self?.handleMouse(event) }
        }) {
            monitors.append(monitor)
        }

        let timer = Timer(timeInterval: 0.22, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        hoverTimer?.invalidate()
        hoverTimer = nil
        manager.isUserDragging = false
    }

    private func handleMouse(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let global = CGEvent(source: nil)?.location ?? .zero
            downPoint = global
            didDrag = false
            if let window = AX.window(at: global) {
                let pid = AX.pid(of: window)
                downWindowID = "\(pid)-\(CFHash(window))"
            } else {
                downWindowID = nil
            }
            manager.isUserDragging = true
        case .leftMouseDragged:
            if let downPoint {
                let global = CGEvent(source: nil)?.location ?? .zero
                if hypot(global.x - downPoint.x, global.y - downPoint.y) > 12 { didDrag = true }
            }
        case .leftMouseUp:
            manager.isUserDragging = false
            let global = CGEvent(source: nil)?.location ?? .zero
            defer {
                downPoint = nil
                downWindowID = nil
                didDrag = false
            }
            guard didDrag, let startID = downWindowID else {
                manager.reconcile()
                return
            }
            let commandDown = event.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.command)
            if commandDown, let target = AX.window(at: global) {
                let pid = AX.pid(of: target)
                let targetID = "\(pid)-\(CFHash(target))"
                if targetID != startID {
                    manager.swapWindows(startID, targetID)
                    return
                }
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
        guard prefs.settings.activateOnHover, !manager.isUserDragging, !manager.isPaused else {
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
