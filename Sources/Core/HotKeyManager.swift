import AppKit
import Carbon.HIToolbox

enum HotKeyAction: String, CaseIterable, Identifiable {
    case swapLeft, swapRight, swapUp, swapDown
    case bigger, smaller, resetSize
    case nextWindow, previousWindow
    case stackNext, stackPrevious
    case floatToggle
    case focusMode
    case noPeek
    case cleanSpace
    case retile
    case nextLayout, previousLayout
    case overview
    case count1, count2, count3, count4, count5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swapLeft: return "Swap with window on the left"
        case .swapRight: return "Swap with window on the right"
        case .swapUp: return "Swap with window above"
        case .swapDown: return "Swap with window below"
        case .bigger: return "Make main window bigger"
        case .smaller: return "Make main window smaller"
        case .resetSize: return "Reset window sizes"
        case .nextWindow: return "Activate next window"
        case .previousWindow: return "Activate previous window"
        case .stackNext: return "Show next window in stack"
        case .stackPrevious: return "Show previous window in stack"
        case .floatToggle: return "Float or tile active window"
        case .focusMode: return "Toggle Focus mode"
        case .noPeek: return "Toggle No Peek"
        case .cleanSpace: return "Toggle Clean Space"
        case .retile: return "Retile this screen"
        case .nextLayout: return "Next layout"
        case .previousLayout: return "Previous layout"
        case .overview: return "Open window overview"
        case .count1: return "Tile 1 window"
        case .count2: return "Tile up to 2 windows"
        case .count3: return "Tile up to 3 windows"
        case .count4: return "Tile up to 4 windows"
        case .count5: return "Tile up to 5 windows"
        }
    }

    var keyGlyph: String {
        switch self {
        case .swapLeft: return "←"
        case .swapRight: return "→"
        case .swapUp: return "↑"
        case .swapDown: return "↓"
        case .bigger: return "="
        case .smaller: return "-"
        case .resetSize: return "0"
        case .nextWindow: return "]"
        case .previousWindow: return "["
        case .stackNext: return "`"
        case .stackPrevious: return "⇧`"
        case .floatToggle: return "F"
        case .focusMode: return "Z"
        case .noPeek: return "D"
        case .cleanSpace: return "P"
        case .retile: return "R"
        case .nextLayout: return "L"
        case .previousLayout: return "⇧L"
        case .overview: return "Space"
        case .count1, .count2, .count3, .count4, .count5: return String(keyGlyphDigit)
        }
    }

    private var keyGlyphDigit: Int {
        switch self {
        case .count1: return 1
        case .count2: return 2
        case .count3: return 3
        case .count4: return 4
        case .count5: return 5
        default: return 0
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .swapLeft: return UInt32(kVK_LeftArrow)
        case .swapRight: return UInt32(kVK_RightArrow)
        case .swapUp: return UInt32(kVK_UpArrow)
        case .swapDown: return UInt32(kVK_DownArrow)
        case .bigger: return UInt32(kVK_ANSI_Equal)
        case .smaller: return UInt32(kVK_ANSI_Minus)
        case .resetSize: return UInt32(kVK_ANSI_0)
        case .nextWindow: return UInt32(kVK_ANSI_RightBracket)
        case .previousWindow: return UInt32(kVK_ANSI_LeftBracket)
        case .stackNext: return UInt32(kVK_ANSI_Grave)
        case .stackPrevious: return UInt32(kVK_ANSI_Grave)
        case .floatToggle: return UInt32(kVK_ANSI_F)
        case .focusMode: return UInt32(kVK_ANSI_Z)
        case .noPeek: return UInt32(kVK_ANSI_D)
        case .cleanSpace: return UInt32(kVK_ANSI_P)
        case .retile: return UInt32(kVK_ANSI_R)
        case .nextLayout: return UInt32(kVK_ANSI_L)
        case .previousLayout: return UInt32(kVK_ANSI_L)
        case .overview: return UInt32(kVK_Space)
        case .count1: return UInt32(kVK_ANSI_1)
        case .count2: return UInt32(kVK_ANSI_2)
        case .count3: return UInt32(kVK_ANSI_3)
        case .count4: return UInt32(kVK_ANSI_4)
        case .count5: return UInt32(kVK_ANSI_5)
        }
    }

    var extraModifiers: UInt32 {
        switch self {
        case .stackPrevious, .previousLayout:
            return UInt32(shiftKey)
        default:
            return 0
        }
    }

    var isCountAction: Bool {
        switch self {
        case .count1, .count2, .count3, .count4, .count5: return true
        default: return false
        }
    }
}

@MainActor
final class HotKeyManager {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var actionByID: [UInt32: HotKeyAction] = [:]
    private var nextID: UInt32 = 1
    private(set) var failures: [HotKeyAction] = []

    var onAction: ((HotKeyAction) -> Void)?

    private static let signature: OSType = 0x4F524C45 // 'ORLE'

    init() {
        installEventHandler()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleEvent(id: hotKeyID.id)
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private func handleEvent(id: UInt32) {
        guard let action = actionByID[id] else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onAction?(action)
        }
    }

    func register(settings: AppSettings) {
        unregisterAll()
        failures = []
        guard settings.shortcutsEnabled else { return }

        let prefix = settings.shortcutPrefix.carbonModifiers
        for action in HotKeyAction.allCases {
            let modifiers = prefix | action.extraModifiers
            var ref: EventHotKeyRef?
            let id = nextID
            nextID += 1
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            let status = RegisterEventHotKey(action.keyCode, modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                actionByID[id] = action
                hotKeyRefs.append(ref)
            } else {
                failures.append(action)
            }
        }
        if DebugLog.isEnabled, !failures.isEmpty {
            DebugLog.write("hotkeys unavailable: \(failures.map(\.rawValue).joined(separator: ", "))")
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        actionByID.removeAll()
    }
}
