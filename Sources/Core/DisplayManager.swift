import Cocoa
import CoreGraphics

@MainActor
final class DisplayManager {
    static let shared = DisplayManager()

    private(set) var displays: [DisplayInfo] = []
    private(set) var primaryUUID: String?

    private init() {
        reload()
    }

    func reload() {
        let screens = NSScreen.screens
        guard let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first else {
            displays = []
            primaryUUID = nil
            return
        }
        let primaryHeight = primary.frame.maxY

        var result: [DisplayInfo] = []
        for screen in screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            let uuid: String
            if let unmanaged = CGDisplayCreateUUIDFromDisplayID(id) {
                uuid = CFUUIDCreateString(nil, unmanaged.takeRetainedValue()) as String
            } else {
                uuid = "display-\(id)"
            }
            let full = CGDisplayBounds(id)
            let visibleCocoa = screen.visibleFrame
            let visibleTopLeft = CGRect(
                x: visibleCocoa.minX,
                y: primaryHeight - visibleCocoa.maxY,
                width: visibleCocoa.width,
                height: visibleCocoa.height
            )
            let isUltrawide = full.width >= full.height * 1.95
            let isVertical = full.height > full.width
            if screen == primary { primaryUUID = uuid }
            result.append(DisplayInfo(
                id: id,
                uuid: uuid,
                name: screen.localizedName,
                frame: full,
                visibleFrame: visibleTopLeft,
                cocoaFrame: screen.frame,
                scale: screen.backingScaleFactor,
                isUltrawide: isUltrawide,
                isVertical: isVertical
            ))
        }
        displays = result.sorted { lhs, rhs in
            if abs(lhs.frame.minX - rhs.frame.minX) > 1 { return lhs.frame.minX < rhs.frame.minX }
            return lhs.frame.minY < rhs.frame.minY
        }
    }

    func display(containing frame: CGRect) -> DisplayInfo? {
        guard !displays.isEmpty else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let direct = displays.first(where: { $0.frame.contains(center) }) { return direct }

        var best: (DisplayInfo, CGFloat)?
        for display in displays {
            let intersection = display.frame.intersection(frame)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            if best == nil || area > best!.1 { best = (display, area) }
        }
        return best?.0 ?? displays.first
    }

    func display(withUUID uuid: String) -> DisplayInfo? {
        displays.first { $0.uuid == uuid }
    }

    func display(withID id: CGDirectDisplayID) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    func screen(for display: DisplayInfo) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == display.id
        }
    }

    var primary: DisplayInfo? {
        displays.first(where: { $0.uuid == primaryUUID }) ?? displays.first
    }
}
