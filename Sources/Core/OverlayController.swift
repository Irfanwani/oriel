import AppKit

@MainActor
final class OverlayController {
    private let prefs = Preferences.shared
    private let displays = DisplayManager.shared
    private let windows = WindowManager.shared

    private var panels: [String: OverlayPanel] = [:]

    enum Mode {
        case none
        case dim
        case clean
    }

    struct OverlayWindow {
        let id: String
        let frame: CGRect
    }

    func update() {
        guard AX.isTrusted else {
            hideAll()
            return
        }
        displays.reload()
        let ownAppFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        let manager = windows
        let active = manager.activeWindow()
        let settings = prefs.settings
        // Clean Space is a blank canvas for screenshots and calls, so cover
        // every display. No Peek keeps only the active window readable.
        let cleanActive = manager.isCleanSpace && !ownAppFrontmost
        let dimActive = manager.isNoPeek && !ownAppFrontmost
        let paused = manager.isPaused

        var liveKeys = Set<String>()

        for display in displays.displays {
            let mode: Mode
            if cleanActive {
                mode = .clean
            } else if dimActive {
                mode = .dim
            } else {
                mode = .none
            }

            let displayWindows = manager.windows
                .filter { $0.displayUUID == display.uuid && !$0.isFloating }
                .map { OverlayWindow(id: $0.id, frame: $0.frame) }
            let activeFrame = active?.displayUUID == display.uuid ? active?.frame : nil
            // Don't paint borders over Oriel's own Settings, onboarding, or
            // Overview panels. The last active app window is still remembered,
            // but its border would otherwise cut across our windows.
            let shouldShowBorder = !paused && settings.highlight != .none && !ownAppFrontmost
            let shouldShow = mode != .none || shouldShowBorder
            if !shouldShow {
                if let panel = panels[display.uuid] {
                    panel.orderOut(nil)
                }
                continue
            }

            let panel = panel(for: display)
            guard let panel else { continue }
            liveKeys.insert(display.uuid)
            panel.update(
                display: display,
                mode: mode,
                highlight: settings.highlight,
                borderWidth: CGFloat(settings.borderWidth),
                color: NSColor(orielHex: settings.highlightColorHex),
                windows: displayWindows,
                activeFrame: activeFrame,
                cleanColor: NSColor(calibratedWhite: 0.11, alpha: 1),
                dimAmount: CGFloat(settings.noPeekDim)
            )
            panel.orderFrontRegardless()
        }

        for (key, panel) in panels where !liveKeys.contains(key) {
            panel.orderOut(nil)
        }
    }

    func hideAll() {
        for panel in panels.values { panel.orderOut(nil) }
    }

    private func panel(for display: DisplayInfo) -> OverlayPanel? {
        if let existing = panels[display.uuid] {
            if let screen = displays.screen(for: display) {
                existing.setFrame(screen.frame, display: true)
            }
            return existing
        }
        guard let screen = displays.screen(for: display) ?? NSScreen.main else { return nil }
        let panel = OverlayPanel(screen: screen, display: display)
        panels[display.uuid] = panel
        return panel
    }
}

// MARK: - Panel

final class OverlayPanel: NSPanel {
    private let overlayView: OverlayView

    init(screen: NSScreen, display: DisplayInfo) {
        overlayView = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.isFloatingPanel = true
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.contentView = overlayView
        self.setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(display: DisplayInfo,
                mode: OverlayController.Mode,
                highlight: HighlightMode,
                borderWidth: CGFloat,
                color: NSColor,
                windows: [OverlayController.OverlayWindow],
                activeFrame: CGRect?,
                cleanColor: NSColor,
                dimAmount: CGFloat) {
        overlayView.displayInfo = display
        overlayView.mode = mode
        overlayView.highlight = highlight
        overlayView.borderWidth = borderWidth
        overlayView.borderColor = color
        overlayView.windows = windows
        overlayView.activeFrame = activeFrame
        overlayView.cleanColor = cleanColor
        overlayView.dimAmount = dimAmount
        overlayView.needsDisplay = true
    }
}

// MARK: - View

final class OverlayView: NSView {
    var displayInfo: DisplayInfo?
    var mode: OverlayController.Mode = .none
    var highlight: HighlightMode = .none
    var borderWidth: CGFloat = 3
    var borderColor: NSColor = .controlAccentColor
    var windows: [OverlayController.OverlayWindow] = []
    var activeFrame: CGRect?
    var cleanColor: NSColor = NSColor(calibratedWhite: 0.11, alpha: 1)
    var dimAmount: CGFloat = 0.5

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    private func local(_ frame: CGRect) -> CGRect {
        guard let display = displayInfo else { return frame }
        return frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let display = displayInfo else { return }
        let localBounds = CGRect(origin: .zero, size: display.frame.size)

        if mode != .none {
            let fillColor: NSColor
            if mode == .clean {
                fillColor = cleanColor
            } else {
                // Dim only, keeping the active window readable through a hole.
                fillColor = NSColor.black.withAlphaComponent(dimAmount)
            }
            let path = NSBezierPath(rect: localBounds)
            if mode == .dim, let active = activeFrame {
                let hole = local(active).insetBy(dx: -1, dy: -1)
                path.append(NSBezierPath(roundedRect: hole, xRadius: 10, yRadius: 10))
                path.windingRule = .evenOdd
            }
            fillColor.setFill()
            path.fill()
        }

        // Clean Space is a blank canvas; a highlight rectangle would give away
        // the window underneath it.
        guard mode != .clean, highlight != .none, !windows.isEmpty else { return }

        for window in windows {
            let isActive = activeFrame.map { roughlyEqual($0, window.frame) } ?? false
            if highlight == .activeBorder && !isActive { continue }
            if highlight == .glow && !isActive { continue }
            drawBorder(around: local(window.frame), active: isActive, glow: highlight == .glow)
        }
    }

    private func roughlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 &&
        abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    private func drawBorder(around frame: CGRect, active: Bool, glow: Bool) {
        // Straddle the window edge rather than painting over window contents.
        let rect = frame.insetBy(dx: -borderWidth / 2, dy: -borderWidth / 2)
        guard rect.width > 4, rect.height > 4 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        path.lineWidth = borderWidth

        if glow {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = borderColor.withAlphaComponent(0.75)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = .zero
            shadow.set()
            borderColor.withAlphaComponent(0.95).setStroke()
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            borderColor.withAlphaComponent(active ? 0.95 : 0.55).setStroke()
            path.stroke()
        }
    }
}

// MARK: - Colors

extension NSColor {
    convenience init(orielHex hex: String) {
        if hex == "accent" {
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            self.init(srgbRed: accent.redComponent, green: accent.greenComponent, blue: accent.blueComponent, alpha: 1)
            return
        }
        var value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let number = Int(value, radix: 16) else {
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            self.init(srgbRed: accent.redComponent, green: accent.greenComponent, blue: accent.blueComponent, alpha: 1)
            return
        }
        self.init(
            srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }
}
