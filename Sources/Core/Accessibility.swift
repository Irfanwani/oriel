import AppKit
import ApplicationServices
import CoreGraphics

enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func promptForAccess() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func appElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    static func attribute<T>(_ element: AXUIElement, _ name: String, as type: T.Type = T.self) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value else { return nil }
        return value as? T
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name, as: String.self)
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        attribute(element, name, as: Bool.self)
    }

    static func role(of element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute as String)
    }

    static func subrole(of element: AXUIElement) -> String? {
        string(element, kAXSubroleAttribute as String)
    }

    static func title(of element: AXUIElement) -> String {
        string(element, kAXTitleAttribute as String) ?? ""
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef as! AXValue?,
              let sizeValue = sizeRef as! AXValue?
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    @discardableResult
    static func setFrame(_ frame: CGRect, of element: AXUIElement) -> Bool {
        var point = frame.origin
        var size = frame.size
        guard let pointValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        // Size first, then position. Several apps constrain a resize against
        // their current screen position; moving first can make the resize clamp.
        // If either call fails, retry in the opposite order once.
        let sizeOK = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) == .success
        let positionOK = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pointValue) == .success
        if sizeOK && positionOK { return true }
        let retriedPosition = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pointValue) == .success
        let retriedSize = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) == .success
        return retriedPosition && retriedSize
    }

    static func canMove(_ element: AXUIElement) -> Bool {
        var positionSettable = DarwinBoolean(false)
        var sizeSettable = DarwinBoolean(false)
        let p = AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &positionSettable) == .success
        let s = AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable) == .success
        return p && s && positionSettable.boolValue && sizeSettable.boolValue
    }

    static func windowList(pid: pid_t) -> [AXUIElement] {
        let app = appElement(pid: pid)
        return attribute(app, kAXWindowsAttribute as String, as: [AXUIElement].self) ?? []
    }

    static func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedAppRef) == .success,
              let focusedAppRef else { return nil }
        let app = focusedAppRef as! AXUIElement
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef else { return nil }
        return (windowRef as! AXUIElement)
    }

    static func focusedApplicationPID() -> pid_t? {
        let system = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedAppRef) == .success,
              let focusedAppRef else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(focusedAppRef as! AXUIElement, &pid)
        return pid == 0 ? nil : pid
    }

    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    static func element(at point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &elementRef)
        guard result == .success, let elementRef else { return nil }
        return elementRef
    }

    static func window(at point: CGPoint) -> AXUIElement? {
        guard let element = element(at: point) else { return nil }
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
           let windowRef {
            let window = windowRef as! AXUIElement
            if role(of: window) == (kAXWindowRole as String) { return window }
        }
        var current: AXUIElement? = element
        for _ in 0..<16 {
            guard let node = current else { break }
            if role(of: node) == (kAXWindowRole as String) { return node }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parentRef) == .success,
               let parentRef {
                current = (parentRef as! AXUIElement)
            } else {
                current = nil
            }
        }
        return nil
    }

    static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        guard role(of: element) == (kAXWindowRole as String) else { return false }
        if let subrole = subrole(of: element) {
            switch subrole {
            case "AXStandardWindow":
                return true
            case "AXDialog", "AXSheet", "AXFloatingWindow", "AXSystemDialog":
                return false
            default:
                break
            }
        }
        // Some apps omit the standard subrole. Require the standard window
        // chrome and resizability before treating it as tileable.
        guard attribute(element, kAXCloseButtonAttribute as String) != nil else { return false }
        return canMove(element)
    }

}

// MARK: - On-screen window index

struct OnScreenWindow {
    let pid: pid_t
    let bounds: CGRect
}

enum ScreenWindowIndex {
    static func current(excluding pid: pid_t) -> [OnScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [OnScreenWindow] = []
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  let alpha = info[kCGWindowAlpha as String] as? NSNumber,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any]
            else { continue }
            if layer.intValue != 0 { continue }
            if alpha.doubleValue < 0.02 { continue }
            let windowPID = pid_t(ownerPID.int32Value)
            if windowPID == pid { continue }
            guard let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            if bounds.width < 80 || bounds.height < 60 { continue }
            result.append(OnScreenWindow(pid: windowPID, bounds: bounds))
        }
        return result
    }

    static func contains(_ window: OnScreenWindow, in list: [OnScreenWindow]) -> Bool {
        list.contains { candidate in
            candidate.pid == window.pid &&
            abs(candidate.bounds.minX - window.bounds.minX) < 8 &&
            abs(candidate.bounds.minY - window.bounds.minY) < 8 &&
            abs(candidate.bounds.width - window.bounds.width) < 8 &&
            abs(candidate.bounds.height - window.bounds.height) < 8
        }
    }
}
