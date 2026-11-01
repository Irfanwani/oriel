import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, layout, appearance, shortcuts, apps, scenes, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .layout: return "Layout"
        case .appearance: return "Appearance"
        case .shortcuts: return "Shortcuts"
        case .apps: return "Apps"
        case .scenes: return "Scenes"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .layout: return "rectangle.3.group"
        case .appearance: return "paintpalette"
        case .shortcuts: return "keyboard"
        case .apps: return "app.badge"
        case .scenes: return "square.stack.3d.up"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var page: SettingsPage = .general
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let model = SettingsModel()

    init(prefs: Preferences,
         manager: WindowManager,
         displays: DisplayManager,
         scenes: SceneManager,
         onChange: @escaping () -> Void) {
        let view = SettingsView(
            prefs: prefs,
            model: model,
            manager: manager,
            displays: displays,
            scenes: scenes,
            onChange: onChange
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Oriel Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 850, height: 640))
        window.minSize = NSSize(width: 780, height: 560)
        window.setFrameAutosaveName("OrielSettingsWindow")
        window.center()
        window.backgroundColor = NSColor.windowBackgroundColor
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(page: SettingsPage? = nil) {
        if let page { model.page = page }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: SettingsModel
    let manager: WindowManager
    let displays: DisplayManager
    let scenes: SceneManager
    let onChange: () -> Void

    @State private var screenList: [DisplayInfo] = []
    @State private var trusted = AX.isTrusted
    @State private var newSceneName = ""
    @State private var loginMessage: String?
    @State private var showResetConfirm = false
    @State private var accessibilityTimer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 208)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    pageHeader
                    pageContent
                }
                .padding(.horizontal, 30)
                .padding(.top, 34)
                .padding(.bottom, 40)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .onAppear(perform: refreshScreens)
        .onReceive(NotificationCenter.default.publisher(for: .orielDisplayConfigurationChanged)) { _ in
            refreshScreens()
        }
        .onReceive(accessibilityTimer) { _ in
            trusted = AX.isTrusted
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Image(nsImage: Brand.icon)
                    .resizable()
                    .frame(width: 25, height: 25)
                Text("Oriel")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 18)
            .padding(.top, 40)
            .padding(.bottom, 20)

            ForEach(SettingsPage.allCases) { page in
                Button {
                    model.page = page
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 19)
                        Text(page.title)
                            .font(.system(size: 12.5, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(model.page == page ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(model.page == page ? Color.primary.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "leaf")
                Text("MIT · v\(Bundle.main.appVersion)")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.page.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(headerSubtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    private var headerSubtitle: String {
        switch model.page {
        case .general: return "How Oriel starts and stays out of your way."
        case .layout: return "Choose how windows share a screen. Every display can be different."
        case .appearance: return "Borders, color and the space between windows."
        case .shortcuts: return "Keyboard-first, when you want it. Silent when you don't."
        case .apps: return "Apps that should float, or stay out of the layout entirely."
        case .scenes: return "Save a whole arrangement and bring it back in one click."
        case .about: return "Native, open source, and built for the Mac."
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch model.page {
        case .general: generalPage
        case .layout: layoutPage
        case .appearance: appearancePage
        case .shortcuts: shortcutsPage
        case .apps: appsPage
        case .scenes: scenesPage
        case .about: aboutPage
        }
    }

    // MARK: - General

    private var generalPage: some View {
        VStack(spacing: 16) {
            SettingsCard {
                SettingsRow(title: "Automatic tiling",
                            subtitle: "Arrange windows as they open, close, or move.") {
                    Toggle("", isOn: Binding(
                        get: { prefs.settings.isEnabled },
                        set: { value in
                            prefs.update { $0.isEnabled = value }
                            onChange()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                Divider().padding(.vertical, 2)
                SettingsRow(title: "Open at login",
                            subtitle: "Start Oriel quietly in the menu bar when you log in.") {
                    Toggle("", isOn: Binding(
                        get: { prefs.settings.openAtLogin },
                        set: { value in
                            prefs.update { $0.openAtLogin = value }
                            let ok = LoginItemManager.setEnabled(value)
                            if !ok {
                                loginMessage = "Move Oriel to Applications to use login items."
                                prefs.update { $0.openAtLogin = false }
                            } else if value, !LoginItemManager.isEnabled {
                                loginMessage = "Allow Oriel in System Settings › General › Login Items."
                            } else {
                                loginMessage = nil
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                if let loginMessage {
                    Text(loginMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Divider().padding(.vertical, 2)
                SettingsRow(title: "Window count in menu",
                            subtitle: "Show how many windows are tiled in the menu header.") {
                    Toggle("", isOn: Binding(
                        get: { prefs.settings.showMenuBarWindowCount },
                        set: { value in
                            prefs.update { $0.showMenuBarWindowCount = value }
                            onChange()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                Divider().padding(.vertical, 2)
                SettingsRow(title: "Accessibility access",
                            subtitle: "Required to read window positions and resize windows.") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(trusted ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(trusted ? "Granted" : "Needed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        if !trusted {
                            Button("Grant") {
                                AX.promptForAccess()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            SettingsCard(title: "This Mac", subtitle: nil) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Connected displays")
                        Spacer()
                        Text("\(screenList.count)")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(screenList) { display in
                        HStack(spacing: 8) {
                            Image(systemName: "display")
                                .foregroundStyle(.secondary)
                            Text(display.name)
                            Spacer()
                            Text(prefs.screenSetting(for: display).layout.title)
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11.5))
                    }
                }
            }

            SettingsCard(title: "Reset", subtitle: "Return every setting to its default. Scenes and app rules are kept.") {
                HStack {
                    Spacer()
                    Button("Reset Settings…") {
                        showResetConfirm = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .confirmationDialog("Reset all Oriel settings?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                prefs.update { settings in
                    let onboarding = settings.hasCompletedOnboarding
                    let scenes = settings.scenes
                    let rules = settings.appRules
                    settings = AppSettings()
                    settings.hasCompletedOnboarding = onboarding
                    settings.scenes = scenes
                    settings.appRules = rules
                }
                onChange()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Layout

    private var layoutPage: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Default layout",
                         subtitle: "A new display starts with this. Picking a layout for one screen in the menu bar stores a per-screen override.") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(LayoutKind.allCases) { layout in
                        LayoutCard(layout: layout, selected: prefs.settings.layout == layout) {
                            prefs.update { $0.layout = layout }
                            onChange()
                        }
                    }
                }
            }

            SettingsCard(title: "Sizing", subtitle: nil) {
                SettingsRow(title: "Windows per screen",
                            subtitle: "Extra windows stack in the last tile.") {
                    HStack(spacing: 8) {
                        Stepper("", value: Binding(
                            get: { prefs.settings.capacity },
                            set: { value in
                                prefs.update { $0.capacity = max(1, min(5, value)) }
                                onChange()
                            }
                        ), in: 1...5)
                        .labelsHidden()
                        Text("\(prefs.settings.capacity)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 18, alignment: .trailing)
                    }
                }
                Divider().padding(.vertical, 2)
                SettingsRow(title: "Main window size",
                            subtitle: "The primary tile's share. Bento and ultrawide Side map this to their own proportions.") {
                    Picker("", selection: Binding(
                        get: { prefs.settings.ratio },
                        set: { value in
                            prefs.update { $0.ratio = value }
                            onChange()
                        }
                    )) {
                        Text("Half").tag(0.5)
                        Text("60%").tag(0.6)
                        Text("Two thirds").tag(0.666)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                Divider().padding(.vertical, 2)
                SettingsRow(title: "Space between windows",
                            subtitle: "The same gap is used around the screen edge.") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { prefs.settings.gap },
                            set: { value in
                                prefs.update { $0.gap = value }
                                onChange()
                            }
                        ), in: 0...24, step: 1)
                        .frame(width: 150)
                        Text("\(Int(prefs.settings.gap)) pt")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                Divider().padding(.vertical, 2)
                SettingsRow(title: "When a screen is full",
                            subtitle: "Choose what happens to the next window.") {
                    Picker("", selection: Binding(
                        get: { prefs.settings.stackMode },
                        set: { value in
                            prefs.update { $0.stackMode = value }
                            onChange()
                        }
                    )) {
                        ForEach(StackMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            SettingsCard(title: "Per-display overrides",
                         subtitle: "The menu bar and \(prefs.settings.shortcutPrefix.displayGlyphs)1–5 set these automatically. Reset a screen to follow the default.") {
                if screenList.isEmpty {
                    Text("No displays found.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(screenList) { display in
                            DisplayOverrideRow(
                                display: display,
                                prefs: prefs,
                                onChange: onChange
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearancePage: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Active window", subtitle: "Drawn in the gap around windows, never over their contents.") {
                Picker("", selection: Binding(
                    get: { prefs.settings.highlight },
                    set: { value in
                        prefs.update { $0.highlight = value }
                        onChange()
                    }
                )) {
                    ForEach(HighlightMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Divider().padding(.vertical, 6)

                HStack {
                    Text("Color")
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(presetColors, id: \.self) { hex in
                            Button {
                                prefs.update { $0.highlightColorHex = hex }
                                onChange()
                            } label: {
                                Circle()
                                    .fill(hex == "accent" ? Color.accentColor : Color(orielHex: hex))
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.primary.opacity(prefs.settings.highlightColorHex == hex ? 0.75 : 0.12), lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        ColorPicker("", selection: Binding(
                            get: { Color(orielHex: prefs.settings.highlightColorHex) },
                            set: { color in
                                prefs.update { $0.highlightColorHex = color.orielHexString }
                                onChange()
                            }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 34)
                    }
                }

                HStack {
                    Text("Thickness")
                    Slider(value: Binding(
                        get: { prefs.settings.borderWidth },
                        set: { value in
                            prefs.update { $0.borderWidth = value }
                            onChange()
                        }
                    ), in: 1...6, step: 0.5)
                    .frame(width: 180)
                    Text(String(format: "%.1f pt", prefs.settings.borderWidth))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 12))
            }

            SettingsCard(title: "No Peek", subtitle: "Fade everything except the window you are working in — useful on calls and screen shares.") {
                HStack {
                    Text("Dim amount")
                    Slider(value: Binding(
                        get: { prefs.settings.noPeekDim },
                        set: { value in
                            prefs.update { $0.noPeekDim = value }
                            onChange()
                        }
                    ), in: 0.1...0.9)
                    .frame(width: 200)
                    Text("\(Int(prefs.settings.noPeekDim * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .font(.system(size: 12))
                Text("Toggle No Peek from the menu bar or with \(prefs.settings.shortcutPrefix.displayGlyphs)D. The dimming overlay is privacy-safe and does not require Screen Recording permission.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: "Preview", subtitle: nil) {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(index == 0 ? 0.08 : 0.04))
                            .frame(height: 76)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(index == 0 ? Color(orielHex: prefs.settings.highlightColorHex) : Color.clear,
                                                  lineWidth: prefs.settings.borderWidth)
                            )
                    }
                }
            }
        }
    }

    private var presetColors: [String] {
        ["accent", "#FF6B6B", "#4ECDC4", "#5E9CFF", "#F7B731", "#A78BFA"]
    }

    // MARK: - Shortcuts

    private var shortcutsPage: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Global shortcuts", subtitle: "Handled by macOS, so Oriel never sees anything else you type.") {
                SettingsRow(title: "Enable shortcuts", subtitle: "Turn every Oriel shortcut on or off.") {
                    Toggle("", isOn: Binding(
                        get: { prefs.settings.shortcutsEnabled },
                        set: { value in
                            prefs.update { $0.shortcutsEnabled = value }
                            onChange()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                Divider().padding(.vertical, 2)
                SettingsRow(title: "Prefix", subtitle: "Every shortcut starts with this.") {
                    Picker("", selection: Binding(
                        get: { prefs.settings.shortcutPrefix },
                        set: { value in
                            prefs.update { $0.shortcutPrefix = value }
                            onChange()
                        }
                    )) {
                        ForEach(ShortcutPrefix.allCases) { prefix in
                            Text(prefix.title).tag(prefix)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
            }

            SettingsCard(title: "All shortcuts", subtitle: "Most actions are also available from the menu bar.") {
                VStack(spacing: 0) {
                    ForEach(HotKeyAction.allCases) { action in
                        HStack {
                            Text(action.title)
                                .font(.system(size: 12))
                            Spacer()
                            Text(shortcutLabel(action))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .padding(.vertical, 5)
                        if action != HotKeyAction.allCases.last {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
    }

    private func shortcutLabel(_ action: HotKeyAction) -> String {
        "\(prefs.settings.shortcutPrefix.displayGlyphs)\(action.keyGlyph)"
    }

    // MARK: - Apps

    private var appsPage: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Floating apps",
                         subtitle: "Their windows are left where you put them and never join the layout.") {
                if prefs.settings.appRules.isEmpty {
                    emptyRow("No floating apps yet.", symbol: "rectangle.dashed")
                } else {
                    VStack(spacing: 8) {
                        ForEach(prefs.settings.appRules) { rule in
                            HStack(spacing: 10) {
                                AppIconView(bundleID: rule.bundleID)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(rule.appName.isEmpty ? rule.bundleID : rule.appName)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(rule.bundleID)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { rule.mode },
                                    set: { value in
                                        prefs.update { s in
                                            if let index = s.appRules.firstIndex(where: { $0.id == rule.id }) {
                                                s.appRules[index].mode = value
                                            }
                                        }
                                        onChange()
                                    }
                                )) {
                                    ForEach(AppRuleMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 140)
                                Button {
                                    prefs.removeAppRule(id: rule.id)
                                    onChange()
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Add App…") { addAppRule() }
                        .buttonStyle(.bordered)
                }
            }

            SettingsCard(title: "Don't tile these apps",
                         subtitle: "Small tools, system panels, and anything you never want stretched.") {
                VStack(spacing: 0) {
                    ForEach(prefs.settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 10) {
                            AppIconView(bundleID: bundleID)
                            Text(appName(for: bundleID))
                                .font(.system(size: 12))
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { prefs.settings.excludedBundleIDs.contains(bundleID) },
                                set: { included in
                                    prefs.update { s in
                                        if included {
                                            if !s.excludedBundleIDs.contains(bundleID) { s.excludedBundleIDs.append(bundleID) }
                                        } else {
                                            s.excludedBundleIDs.removeAll { $0 == bundleID }
                                        }
                                    }
                                    onChange()
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                        .padding(.vertical, 5)
                        Divider().opacity(0.5)
                    }
                }
                HStack {
                    Text("Default exclusions are marked by their bundle identifier. Turn one off to tile it again.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Add App…") { addExclusion() }
                        .buttonStyle(.bordered)
                    Button("Reset Defaults") {
                        prefs.update { $0.excludedBundleIDs = AppSettings.defaultExclusions }
                        onChange()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func emptyRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }

    private func addAppRule() {
        if let picked = pickApplication() {
            prefs.addAppRule(bundleID: picked.bundleID, appName: picked.name)
            onChange()
        }
    }

    private func addExclusion() {
        if let picked = pickApplication() {
            prefs.update { s in
                if !s.excludedBundleIDs.contains(picked.bundleID) {
                    s.excludedBundleIDs.append(picked.bundleID)
                }
            }
            onChange()
        }
    }

    private func pickApplication() -> (bundleID: String, name: String)? {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            return nil
        }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return (bundleID, name)
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }

    // MARK: - Scenes

    private var scenesPage: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Save this moment",
                         subtitle: "A scene remembers open apps, their order, floating windows, and per-display layouts.") {
                HStack(spacing: 10) {
                    TextField("Deep work, Client call, Writing…", text: $newSceneName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveScene)
                    Button("Save Current Scene", action: saveScene)
                        .buttonStyle(.borderedProminent)
                        .disabled(newSceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Restoring launches apps that are closed and tiles the windows that come back. Window contents and document state are never touched.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }

            SettingsCard(title: "Saved scenes", subtitle: nil) {
                if prefs.settings.scenes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No scenes yet")
                            .font(.system(size: 12, weight: .medium))
                        Text("Arrange a few windows, then save the moment.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(prefs.settings.scenes.sorted(by: { $0.createdAt > $1.createdAt })) { scene in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.1))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "square.stack.3d.up")
                                        .foregroundStyle(Color.accentColor)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scene.name)
                                        .font(.system(size: 12.5, weight: .semibold))
                                    Text("\(scene.windows.count) window\(scene.windows.count == 1 ? "" : "s") · \(scene.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore") {
                                    scenes.restore(scene)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Button {
                                    scenes.delete(scene)
                                    onChange()
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 7)
                            if scene.id != prefs.settings.scenes.sorted(by: { $0.createdAt > $1.createdAt }).last?.id {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                }
            }

            SettingsCard(title: "Shortcuts", subtitle: nil) {
                Text("Restore a scene from the menu bar, or use Automation:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Text("oriel scene \"Deep Work\"")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    Spacer()
                }
            }
        }
    }

    private func saveScene() {
        let name = newSceneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        scenes.saveCurrentScene(named: name)
        newSceneName = ""
    }

    // MARK: - About

    private var aboutPage: some View {
        VStack(spacing: 16) {
            SettingsCard {
                HStack(alignment: .top, spacing: 18) {
                    Image(nsImage: Brand.icon)
                        .resizable()
                        .frame(width: 78, height: 78)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oriel")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(Brand.tagline)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("Version \(Bundle.main.appVersion) (\(Bundle.main.buildVersion)) · MIT License")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 3)
                    }
                    Spacer()
                }
            }

            SettingsCard(title: "Why Oriel", subtitle: nil) {
                VStack(alignment: .leading, spacing: 11) {
                    aboutFeature("Auto-tiling that reflows", "Open, close, or move a window and the layout heals itself.")
                    aboutFeature("Five layouts, per display", "Grid, Columns, Rows, Side, and the editorial Bento.")
                    aboutFeature("Scenes and app rules", "Save a whole working arrangement. Keep utility windows floating.")
                    aboutFeature("Overview and Focus", "See every window as a map, or clear everything but the one you need.")
                    aboutFeature("CLI and URL automation", "Script layouts and scenes with oriel:// links.")
                    aboutFeature("No telemetry, no account", "Everything stays on your Mac. Accessibility is used only to position windows.")
                }
            }

            SettingsCard(title: "Links", subtitle: nil) {
                HStack {
                    Link("GitHub", destination: Brand.github)
                    Text("·").foregroundStyle(.tertiary)
                    Link("Report an issue", destination: Brand.github.appendingPathComponent("issues"))
                    Text("·").foregroundStyle(.tertiary)
                    Link("MIT License", destination: Brand.github.appendingPathComponent("blob/main/LICENSE"))
                    Spacer()
                }
                .font(.system(size: 12))
            }

            Text("Built natively with AppKit and SwiftUI. No Electron. No subscription. No tracking.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
    }

    private func aboutFeature(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refreshScreens() {
        DisplayManager.shared.reload()
        screenList = DisplayManager.shared.displays
    }
}

// MARK: - Reusable views

struct SettingsCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 1)
        )
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct LayoutCard: View {
    let layout: LayoutKind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MiniLayout(layout: layout)
                    .frame(width: 52, height: 38)
                    .padding(6)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(layout.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(layout.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DisplayOverrideRow: View {
    let display: DisplayInfo
    @ObservedObject var prefs: Preferences
    let onChange: () -> Void

    var body: some View {
        let setting = prefs.screenSetting(for: display)
        HStack(spacing: 12) {
            Image(systemName: "display")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(.system(size: 12, weight: .medium))
                Text(prefs.settings.hasOverride(for: display.uuid) ? "Custom for this display" : "Following the default")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { prefs.screenSetting(for: display).layout },
                set: { value in
                    prefs.setScreenLayout(value, for: display)
                    onChange()
                }
            )) {
                ForEach(LayoutKind.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            .labelsHidden()
            .frame(width: 112)
            Stepper("", value: Binding(
                get: { prefs.screenSetting(for: display).capacity },
                set: { value in
                    prefs.setScreenCapacity(value, for: display)
                    onChange()
                }
            ), in: 1...max(1, setting.layout.maxTiles(on: display)))
            .labelsHidden()
            Text("\(setting.capacity)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 14)
            if prefs.settings.hasOverride(for: display.uuid) {
                Button("Reset") {
                    prefs.clearOverride(for: display)
                    onChange()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

struct AppIconView: View {
    let bundleID: String

    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "app")
                    .resizable()
                    .padding(3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
    }
}
