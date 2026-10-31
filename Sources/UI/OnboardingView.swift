import AppKit
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step = 0
    @Published var granted = AX.isTrusted
}

@MainActor
final class OnboardingWindowController: NSWindowController {
    private let model = OnboardingModel()
    private let prefs: Preferences

    init(prefs: Preferences,
         onGrant: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onFinish: @escaping () -> Void) {
        self.prefs = prefs
        let view = OnboardingView(
            prefs: prefs,
            model: model,
            onGrant: onGrant,
            onOpenSettings: onOpenSettings,
            onFinish: onFinish
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "Oriel"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 780, height: 540))
        window.minSize = NSSize(width: 780, height: 540)
        window.maxSize = NSSize(width: 780, height: 540)
        window.center()
        window.level = .normal
        window.backgroundColor = NSColor.windowBackgroundColor
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func granted() {
        model.granted = true
        model.step = max(model.step, 2)
    }

    func markPermissionGranted() {
        model.granted = true
    }

    func dismiss() {
        window?.orderOut(nil)
    }
}

struct OnboardingView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: OnboardingModel
    let onGrant: () -> Void
    let onOpenSettings: () -> Void
    let onFinish: () -> Void

    @State private var chosenLayout: LayoutKind = .grid
    @State private var gap: Double = 8
    @State private var launchAtLogin = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 286)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 780, height: 540)
        .ignoresSafeArea()
        .onAppear {
            chosenLayout = prefs.settings.layout
            gap = prefs.settings.gap
            launchAtLogin = prefs.settings.openAtLogin
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: Brand.icon)
                    .resizable()
                    .frame(width: 34, height: 34)
                Text("Oriel")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.top, 54)

            Spacer()

            Text("A calmer\ndesktop.")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineSpacing(-4)

            Text("Every window, in its place.\nNo setup. No fiddling.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.top, 18)
                .lineSpacing(4)

            Spacer()

            HStack(spacing: 7) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Open source · MIT")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 7) {
                Image(systemName: "lock.shield")
                Text("No account · No telemetry")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.42))
            .padding(.top, 7)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 34)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.11),
                         Color(red: 0.13, green: 0.15, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                stepDots
                Spacer()
                Text("\(model.step + 1) of 3")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 38)

            Group {
                switch model.step {
                case 0: welcome
                case 1: permission
                default: layout
                }
            }
            .padding(.top, 38)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 52)
        .padding(.bottom, 30)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index == model.step ? Color.accentColor : Color.primary.opacity(0.13))
                    .frame(width: index == model.step ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: model.step)
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Windows that\narrange themselves.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineSpacing(-2)
            Text("Open a window. Oriel gives it a place. Close one, and the rest fill the space. Your desktop stays tidy without a single drag.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                feature("rectangle.3.group", "Grid, Columns, Rows, Side and Bento")
                feature("arrow.triangle.2.circlepath", "Reflows automatically as windows open and close")
                feature("square.on.square", "Stacks extra windows without shrinking your tiles")
                feature("sparkles", "Scenes, app rules, overview and CLI automation")
            }
            .padding(.top, 28)

            Spacer()

            HStack {
                Text("macOS 14 or later")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                primaryButton("Get started") {
                    withAnimation { model.step = 1 }
                }
            }
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("One permission.\nNothing more.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineSpacing(-2)
            Text("macOS only lets an app move another app's windows after you allow it in Accessibility. Oriel uses that access to set window position and size — nothing else.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                privacyRow("lock.shield", "Never reads what is inside your windows")
                privacyRow("keyboard", "Never records what you type")
                privacyRow("network.slash", "No analytics, no account, no network calls")
            }
            .padding(.top, 24)

            HStack(spacing: 10) {
                if model.granted {
                    Label("Accessibility granted", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Label("Waiting for permission", systemImage: "clock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 26)

            Spacer()

            HStack(spacing: 10) {
                secondaryButton("Open System Settings", action: onOpenSettings)
                Spacer()
                if model.granted {
                    primaryButton("Continue") {
                        withAnimation { model.step = 2 }
                    }
                } else {
                    primaryButton("Grant Accessibility", action: onGrant)
                }
            }
        }
    }

    private var layout: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pick your first layout.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineSpacing(-2)
            Text("Oriel starts in Grid: one main window with the rest folded beside it. Change it any time from the menu bar.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(LayoutKind.allCases) { item in
                    Button {
                        chosenLayout = item
                    } label: {
                        HStack(spacing: 10) {
                            MiniLayout(layout: item)
                                .frame(width: 38, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(item.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if chosenLayout == item {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(chosenLayout == item ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(chosenLayout == item ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 22)

            HStack {
                Text("Space between windows")
                    .font(.system(size: 12, weight: .medium))
                Slider(value: $gap, in: 0...24, step: 1)
                    .frame(width: 150)
                Text("\(Int(gap)) pt")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.top, 20)

            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open at login")
                        .font(.system(size: 12, weight: .medium))
                    Text("Keep your desktop tidy from the first window.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.top, 18)

            Spacer()

            HStack {
                Text("You can change everything later.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                primaryButton("Start tiling") {
                    prefs.update { settings in
                        settings.layout = chosenLayout
                        settings.capacity = 3
                        settings.gap = gap
                        settings.openAtLogin = launchAtLogin
                        settings.isEnabled = true
                        settings.hasCompletedOnboarding = true
                    }
                    onFinish()
                }
            }
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary.opacity(0.84))
        }
    }

    private func privacyRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 9)
            .background(Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
