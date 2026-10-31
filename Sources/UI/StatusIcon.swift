import AppKit

enum StatusIcon {
    static func image(layout: LayoutKind, paused: Bool) -> NSImage {
        let size = CGSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.black.setFill()
            if paused {
                let bar = NSBezierPath(roundedRect: CGRect(x: 5, y: 4, width: 2.6, height: 10), xRadius: 1, yRadius: 1)
                bar.fill()
                let bar2 = NSBezierPath(roundedRect: CGRect(x: 10.4, y: 4, width: 2.6, height: 10), xRadius: 1, yRadius: 1)
                bar2.fill()
                return true
            }
            let display = DisplayInfo(
                id: 0, uuid: "", name: "",
                frame: CGRect(origin: .zero, size: CGSize(width: 100, height: 100)),
                visibleFrame: CGRect(origin: .zero, size: CGSize(width: 100, height: 100)),
                cocoaFrame: .zero, scale: 2,
                isUltrawide: layout == .columns, isVertical: false
            )
            let input = LayoutEngine.Input(bounds: display.visibleFrame, count: 3, ratio: 0.5, gap: 4,
                                           isUltrawide: display.isUltrawide, isVertical: false)
            let frames = LayoutEngine.frames(for: layout, input: input)
            let scaleX = rect.width / 100
            let scaleY = rect.height / 100
            for frame in frames.prefix(4) {
                let local = CGRect(x: frame.minX * scaleX, y: frame.minY * scaleY,
                                   width: frame.width * scaleX, height: frame.height * scaleY)
                let path = NSBezierPath(roundedRect: local.insetBy(dx: 0.4, dy: 0.4), xRadius: 1.2, yRadius: 1.2)
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
