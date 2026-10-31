import AppKit
import SwiftUI

@MainActor
final class HUDController {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let displays = DisplayManager.shared

    func show(title: String, subtitle: String, layout: LayoutKind? = nil, symbol: String? = nil) {
        let view = HUDView(title: title, subtitle: subtitle, layout: layout, symbol: symbol)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 76)

        if panel == nil {
            let p = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .statusBar
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            panel = p
        }
        guard let panel else { return }

        panel.contentView = hosting
        let activeDisplay = WindowManager.shared.activeDisplay() ?? displays.primary
        let screen = activeDisplay.flatMap { displays.screen(for: $0) } ?? NSScreen.main
        if let screen {
            let x = screen.visibleFrame.midX - 160
            let y = screen.visibleFrame.minY + 26
            panel.setFrame(CGRect(x: x, y: y, width: 320, height: 76), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: work)
    }
}

struct HUDView: View {
    let title: String
    let subtitle: String
    let layout: LayoutKind?
    let symbol: String?

    var body: some View {
        HStack(spacing: 13) {
            if let layout {
                MiniLayout(layout: layout)
                    .frame(width: 42, height: 32)
            } else {
                Image(systemName: symbol ?? "rectangle.3.group")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(width: 320, height: 76)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

struct MiniLayout: View {
    let layout: LayoutKind

    var body: some View {
        Canvas { context, size in
            let display = DisplayInfo(
                id: 0, uuid: "", name: "",
                frame: CGRect(origin: .zero, size: CGSize(width: 100, height: 64)),
                visibleFrame: CGRect(origin: .zero, size: CGSize(width: 100, height: 64)),
                cocoaFrame: .zero, scale: 2,
                isUltrawide: layout == .columns,
                isVertical: false
            )
            let input = LayoutEngine.Input(
                bounds: display.visibleFrame,
                count: min(layout.maxTiles(on: display), 4),
                ratio: 0.5,
                gap: 3,
                isUltrawide: display.isUltrawide,
                isVertical: false
            )
            let frames = LayoutEngine.frames(for: layout, input: input)
            let scaleX = size.width / 100
            let scaleY = size.height / 64
            for (index, frame) in frames.enumerated() {
                let rect = CGRect(x: frame.minX * scaleX, y: frame.minY * scaleY,
                                  width: frame.width * scaleX, height: frame.height * scaleY)
                let path = Path(roundedRect: rect, cornerRadius: 2)
                context.fill(path, with: .color(.primary.opacity(index == 0 ? 0.9 : 0.38)))
            }
        }
    }
}
