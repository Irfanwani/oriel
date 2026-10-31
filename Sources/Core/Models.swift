import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import Carbon.HIToolbox

// MARK: - Layouts

enum LayoutKind: String, Codable, CaseIterable, Identifiable {
    case grid
    case columns
    case rows
    case side
    case bento

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "Grid"
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .side: return "Side"
        case .bento: return "Bento"
        }
    }

    var subtitle: String {
        switch self {
        case .grid: return "A hero window plus a folded stack"
        case .columns: return "Side by side, full height"
        case .rows: return "Full width, stacked top to bottom"
        case .side: return "A main window with a rail"
        case .bento: return "A composed, editorial arrangement"
        }
    }

    var symbolName: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .columns: return "rectangle.split.3x1"
        case .rows: return "rectangle.split.1x3"
        case .side: return "rectangle.leadinghalf.inset.filled"
        case .bento: return "rectangle.3.group"
        }
    }

    /// Maximum number of tiles this layout can show. Extra windows stack.
    func maxTiles(on display: DisplayInfo) -> Int {
        switch self {
        case .grid: return 4
        case .columns: return display.isUltrawide ? 4 : 3
        case .rows: return display.isVertical ? 3 : 3
        case .side: return display.isUltrawide ? 5 : (display.isVertical ? 5 : 4)
        case .bento: return 4
        }
    }
}

enum StackMode: String, Codable, CaseIterable, Identifiable {
    case stack
    case float

    var id: String { rawValue }
    var title: String {
        switch self {
        case .stack: return "Stack in the last tile"
        case .float: return "Float over the layout"
        }
    }
}

enum HighlightMode: String, Codable, CaseIterable, Identifiable {
    case none
    case activeBorder
    case allBorders
    case glow

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .activeBorder: return "Border on active"
        case .allBorders: return "Border on all"
        case .glow: return "Glow on active"
        }
    }
}

enum ShortcutPrefix: String, Codable, CaseIterable, Identifiable {
    case controlOption
    case optionCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlOption: return "⌃⌥  Control + Option"
        case .optionCommand: return "⌥⌘  Option + Command"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .controlOption: return UInt32(controlKey | optionKey)
        case .optionCommand: return UInt32(optionKey | cmdKey)
        }
    }

    var displayGlyphs: String {
        switch self {
        case .controlOption: return "⌃⌥"
        case .optionCommand: return "⌥⌘"
        }
    }

    var modifierFlags: NSEvent.ModifierFlags {
        switch self {
        case .controlOption: return [.control, .option]
        case .optionCommand: return [.option, .command]
        }
    }
}

enum AppRuleMode: String, Codable, CaseIterable, Identifiable {
    case float
    case tile

    var id: String { rawValue }
    var title: String {
        switch self {
        case .float: return "Keep floating"
        case .tile: return "Tile normally"
        }
    }
}

struct AppRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var bundleID: String
    var appName: String
    var mode: AppRuleMode = .float
    var titlePrefix: String? = nil
}

struct ScreenSetting: Codable, Equatable {
    var layout: LayoutKind
    var capacity: Int
    var ratio: Double
}

struct SceneWindow: Codable, Equatable {
    var bundleID: String
    var appName: String
    var displayUUID: String
    var order: Int
    var floating: Bool = false
    /// Saved position for floating windows. Tiled windows are placed by the
    /// layout engine, so their frame is intentionally not restored.
    var frame: CGRect? = nil
}

struct SavedScene: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var windows: [SceneWindow] = []
    var screenOverrides: [String: ScreenSetting] = [:]
}

// MARK: - Settings

struct AppSettings: Codable, Equatable {
    var isEnabled: Bool = true
    var layout: LayoutKind = .grid
    var capacity: Int = 3
    var ratio: Double = 0.5
    var gap: Double = 8

    var stackMode: StackMode = .stack

    var highlight: HighlightMode = .activeBorder
    var highlightColorHex: String = "accent"
    var borderWidth: Double = 3

    var noPeekDim: Double = 0.5

    var shortcutsEnabled: Bool = true
    var shortcutPrefix: ShortcutPrefix = .controlOption
    var activateOnHover: Bool = false
    var hoverDelay: Double = 0.35

    var openAtLogin: Bool = false
    var showMenuBarWindowCount: Bool = true
    var hasCompletedOnboarding: Bool = false

    var excludedBundleIDs: [String] = AppSettings.defaultExclusions
    var appRules: [AppRule] = []
    var scenes: [SavedScene] = []
    var screenOverrides: [String: ScreenSetting] = [:]

    static let defaultExclusions: [String] = [
        "com.apple.calculator",
        "com.apple.systempreferences",
        "com.apple.Stickies",
        "com.apple.PhotoBooth",
        "com.apple.QuickTimePlayerX",
        "com.apple.iphonesimulator",
        "com.apple.clock",
        "com.apple.DigitalColorMeter",
        "com.apple.Screenshot",
        "com.apple.ArchiveUtility",
        "com.apple.Installer",
        "com.apple.Magnifier",
        "com.apple.ScreenContinuity",
        "com.apple.LKDeskView",
        "com.apple.VoiceOverUtility"
    ]

    func effectiveScreen(for uuid: String) -> ScreenSetting {
        screenOverrides[uuid] ?? ScreenSetting(layout: layout, capacity: capacity, ratio: ratio)
    }

    func hasOverride(for uuid: String) -> Bool {
        screenOverrides[uuid] != nil
    }

    // Tolerant decoding: settings added in later versions should never wipe a file.
    enum CodingKeys: String, CodingKey {
        case isEnabled, layout, capacity, ratio, gap, stackMode
        case highlight, highlightColorHex, borderWidth
        case noPeekDim
        case shortcutsEnabled, shortcutPrefix, activateOnHover, hoverDelay
        case openAtLogin, showMenuBarWindowCount, hasCompletedOnboarding
        case excludedBundleIDs, appRules, scenes, screenOverrides
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
        layout = (try? c.decodeIfPresent(LayoutKind.self, forKey: .layout)) ?? .grid
        capacity = (try? c.decodeIfPresent(Int.self, forKey: .capacity)) ?? 3
        ratio = (try? c.decodeIfPresent(Double.self, forKey: .ratio)) ?? 0.5
        gap = (try? c.decodeIfPresent(Double.self, forKey: .gap)) ?? 8
        stackMode = (try? c.decodeIfPresent(StackMode.self, forKey: .stackMode)) ?? .stack
        highlight = (try? c.decodeIfPresent(HighlightMode.self, forKey: .highlight)) ?? .activeBorder
        highlightColorHex = (try? c.decodeIfPresent(String.self, forKey: .highlightColorHex)) ?? "accent"
        borderWidth = (try? c.decodeIfPresent(Double.self, forKey: .borderWidth)) ?? 3
        noPeekDim = (try? c.decodeIfPresent(Double.self, forKey: .noPeekDim)) ?? 0.5
        shortcutsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .shortcutsEnabled)) ?? true
        shortcutPrefix = (try? c.decodeIfPresent(ShortcutPrefix.self, forKey: .shortcutPrefix)) ?? .controlOption
        activateOnHover = (try? c.decodeIfPresent(Bool.self, forKey: .activateOnHover)) ?? false
        hoverDelay = (try? c.decodeIfPresent(Double.self, forKey: .hoverDelay)) ?? 0.35
        openAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .openAtLogin)) ?? false
        showMenuBarWindowCount = (try? c.decodeIfPresent(Bool.self, forKey: .showMenuBarWindowCount)) ?? true
        hasCompletedOnboarding = (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)) ?? false
        excludedBundleIDs = (try? c.decodeIfPresent([String].self, forKey: .excludedBundleIDs)) ?? AppSettings.defaultExclusions
        appRules = (try? c.decodeIfPresent([AppRule].self, forKey: .appRules)) ?? []
        scenes = (try? c.decodeIfPresent([SavedScene].self, forKey: .scenes)) ?? []
        screenOverrides = (try? c.decodeIfPresent([String: ScreenSetting].self, forKey: .screenOverrides)) ?? [:]
    }
}

// MARK: - Runtime window model

struct ManagedWindow {
    let id: String
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let appName: String
    var title: String
    var frame: CGRect
    var displayUUID: String
    var isFloating: Bool
    var order: Int
    var icon: NSImage?

}

struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    /// Top-left-origin frame in the global display space.
    let frame: CGRect
    /// Usable area (menu bar, Dock and Stage Manager excluded), top-left origin.
    let visibleFrame: CGRect
    let cocoaFrame: CGRect
    let scale: CGFloat
    let isUltrawide: Bool
    let isVertical: Bool

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame && lhs.visibleFrame == rhs.visibleFrame
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let orielSettingsChanged = Notification.Name("app.oriel.settingsChanged")
    static let orielDisplayConfigurationChanged = Notification.Name("app.oriel.displayConfigurationChanged")
}

// MARK: - Version

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    var buildVersion: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
