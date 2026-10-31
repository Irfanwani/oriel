import AppKit

@MainActor
final class OverviewController {
    private var panel: OverviewPanel?
    private var windows: [ManagedWindow] = []
    private var display: DisplayInfo?
    private var selectedID: String?
    private let manager = WindowManager.shared

    var hud: HUDController?
    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard AX.isTrusted else { return }
        guard let display = manager.activeDisplay() ?? DisplayManager.shared.primary else { return }
        self.display = display
        windows = manager.overviewWindows(for: display)
        guard !windows.isEmpty else {
            hud?.show(title: "Nothing to overview", subtitle: "Open a window first", layout: nil, symbol: "rectangle.on.rectangle.slash")
            return
        }
        selectedID = windows.first(where: { $0.id == manager.activeWindowID })?.id ?? windows.first?.id
        guard let screen = DisplayManager.shared.screen(for: display) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let panel = OverviewPanel(frame: frame)
        let view = OverviewCanvasView(frame: CGRect(origin: .zero, size: frame.size))
        view.displayInfo = display
        view.windows = windows
        view.selectedID = selectedID
        view.onFocus = { [weak self] id in
            self?.focus(id)
        }
        view.onClose = { [weak self] in
            self?.close()
        }
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(view)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        windows = []
        selectedID = nil
    }

    private func focus(_ id: String) {
        manager.focus(windowID: id)
        close()
    }

    func refresh() {
        guard isVisible, let display else { return }
        windows = manager.overviewWindows(for: display)
        if let view = panel?.contentView as? OverviewCanvasView {
            view.windows = windows
            if !windows.contains(where: { $0.id == selectedID }) {
                selectedID = windows.first?.id
                view.selectedID = selectedID
            }
            view.needsDisplay = true
        }
    }
}

final class OverviewPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.level = .modalPanel
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isFloatingPanel = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

final class OverviewCanvasView: NSView {
    var displayInfo: DisplayInfo?
    var windows: [ManagedWindow] = []
    var selectedID: String?
    var onFocus: ((String) -> Void)?
    var onClose: (() -> Void)?

    private var cardRects: [(ManagedWindow, CGRect)] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let display = displayInfo else { return }
        let accent = NSColor.controlAccentColor

        NSColor.black.withAlphaComponent(0.62).setFill()
        bounds.fill()

        let header = NSRect(x: 48, y: 34, width: bounds.width - 96, height: 60)
        let title = "Overview"
        let subtitle = "\(display.name) · \(windows.count) window\(windows.count == 1 ? "" : "s")"
        title.draw(at: header.origin, withAttributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
        subtitle.draw(at: CGPoint(x: header.minX, y: header.minY + 32), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55)
        ])

        let hint = "↩ focus   ·   arrows move   ·   space cycles   ·   esc closes"
        let hintSize = hint.size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)])
        hint.draw(at: CGPoint(x: bounds.width - hintSize.width - 48, y: 42), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.42)
        ])

        let top: CGFloat = 118
        let bottom: CGFloat = 54
        let side: CGFloat = 56
        let available = CGRect(x: side, y: top, width: bounds.width - side * 2, height: bounds.height - top - bottom)
        let scale = min(available.width / display.visibleFrame.width, available.height / display.visibleFrame.height)
        let stageWidth = display.visibleFrame.width * scale
        let stageHeight = display.visibleFrame.height * scale
        let stageOrigin = CGPoint(x: available.midX - stageWidth / 2, y: available.midY - stageHeight / 2)

        // A subtle outline of the screen.
        let stage = CGRect(origin: stageOrigin, size: CGSize(width: stageWidth, height: stageHeight))
        let stagePath = NSBezierPath(roundedRect: stage, xRadius: 14, yRadius: 14)
        NSColor.white.withAlphaComponent(0.035).setFill()
        stagePath.fill()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        stagePath.lineWidth = 1
        stagePath.stroke()

        cardRects.removeAll()
        let sorted = windows.sorted { lhs, rhs in
            if lhs.id == selectedID { return false }
            if rhs.id == selectedID { return true }
            return lhs.frame.minY < rhs.frame.minY
        }
        for window in sorted {
            let relative = CGRect(
                x: window.frame.minX - display.visibleFrame.minX,
                y: window.frame.minY - display.visibleFrame.minY,
                width: window.frame.width,
                height: window.frame.height
            )
            // Stacked windows share a tile. Fan them a few points so every
            // card is visible and clickable instead of disappearing underneath.
            let stack = windows.filter { roughlyEqual($0.frame, window.frame) }
            let stackIndex = stack.firstIndex(where: { $0.id == window.id }) ?? 0
            let offset = CGFloat(stackIndex) * 7
            let rect = CGRect(
                x: stage.minX + relative.minX * scale + 3 + offset,
                y: stage.minY + relative.minY * scale + 3 + offset,
                width: max(36, relative.width * scale - 6),
                height: max(30, relative.height * scale - 6)
            )
            cardRects.append((window, rect))
            drawCard(window: window, in: rect, selected: window.id == selectedID, accent: accent)
        }
    }

    private func roughlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 &&
        abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    private func drawCard(window: ManagedWindow, in rect: CGRect, selected: Bool, accent: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        if selected {
            accent.withAlphaComponent(0.26).setFill()
        } else {
            NSColor.white.withAlphaComponent(0.10).setFill()
        }
        path.fill()
        (selected ? accent : NSColor.white.withAlphaComponent(0.13)).setStroke()
        path.lineWidth = selected ? 2 : 1
        path.stroke()

        let iconSize: CGFloat = min(26, max(14, rect.height * 0.24))
        if let icon = window.icon {
            icon.draw(in: CGRect(x: rect.minX + 10, y: rect.minY + 9, width: iconSize, height: iconSize),
                      from: .zero, operation: .sourceOver, fraction: 1)
        }
        let titleRect = CGRect(x: rect.minX + 10 + iconSize + 7, y: rect.minY + 9,
                               width: rect.width - iconSize - 34, height: iconSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let title = window.title.isEmpty ? window.appName : window.title
        (title as NSString).draw(in: titleRect, withAttributes: [
            .font: NSFont.systemFont(ofSize: max(9, min(12, rect.height * 0.1)), weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            .paragraphStyle: paragraph
        ])

        if rect.width > 150, rect.height > 74 {
            let app = window.appName
            (app as NSString).draw(in: CGRect(x: rect.minX + 10, y: rect.maxY - 24,
                                              width: rect.width - 50, height: 16),
                                   withAttributes: [
                                       .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                                       .foregroundColor: NSColor.white.withAlphaComponent(0.42),
                                       .paragraphStyle: paragraph
                                   ])
        }

        let stackCount = windows.filter { roughlyEqual($0.frame, window.frame) }.count
        if stackCount > 1, rect.width > 120, rect.height > 70 {
            let stackBadge = "×\(stackCount)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.65)
            ]
            let size = stackBadge.size(withAttributes: attrs)
            stackBadge.draw(at: CGPoint(x: rect.maxX - size.width - 9, y: rect.maxY - 24), withAttributes: attrs)
        }

        if let index = windows.firstIndex(where: { $0.id == window.id }), index < 9 {
            let badge = "\(index + 1)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(selected ? 0.95 : 0.55)
            ]
            let size = badge.size(withAttributes: attrs)
            badge.draw(at: CGPoint(x: rect.maxX - size.width - 9, y: rect.minY + 8), withAttributes: attrs)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onClose?()
        case 36, 76:
            if let selectedID { onFocus?(selectedID) }
        case 123:
            moveSelection(dx: -1, dy: 0)
        case 124:
            moveSelection(dx: 1, dy: 0)
        case 125:
            moveSelection(dx: 0, dy: 1)
        case 126:
            moveSelection(dx: 0, dy: -1)
        case 48:
            cycleSelection()
        default:
            if let characters = event.charactersIgnoringModifiers,
               let number = Int(characters), number >= 1, number <= windows.count {
                selectedID = windows[number - 1].id
                needsDisplay = true
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = cardRects.last(where: { $0.1.contains(point) }) {
            selectedID = hit.0.id
            needsDisplay = true
            onFocus?(hit.0.id)
        } else {
            onClose?()
        }
    }

    private func moveSelection(dx: CGFloat, dy: CGFloat) {
        guard !windows.isEmpty else { return }
        let current = windows.first(where: { $0.id == selectedID }) ?? windows[0]
        let origin = CGPoint(x: current.frame.midX, y: current.frame.midY)
        var best: (ManagedWindow, CGFloat)?
        for window in windows where window.id != current.id {
            let point = CGPoint(x: window.frame.midX, y: window.frame.midY)
            let deltaX = point.x - origin.x
            let deltaY = point.y - origin.y
            let ahead: Bool
            if dx < 0 { ahead = deltaX < -10 }
            else if dx > 0 { ahead = deltaX > 10 }
            else if dy < 0 { ahead = deltaY < -10 }
            else { ahead = deltaY > 10 }
            guard ahead else { continue }
            let distance = abs(deltaX) + abs(deltaY)
            if best == nil || distance < best!.1 { best = (window, distance) }
        }
        if let best {
            selectedID = best.0.id
            needsDisplay = true
        }
    }

    private func cycleSelection() {
        guard !windows.isEmpty else { return }
        let index = windows.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = windows[(index + 1) % windows.count].id
        needsDisplay = true
    }
}
