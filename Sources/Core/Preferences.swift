import Foundation
import Combine

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            scheduleSave()
            NotificationCenter.default.post(name: .orielSettingsChanged, object: nil)
        }
    }

    private(set) var configURL: URL
    private var saveWorkItem: DispatchWorkItem?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Oriel", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        if copy != settings { settings = copy }
    }

    func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            let data = try encoder.encode(settings)
            try data.write(to: configURL, options: [.atomic])
        } catch {
            NSLog("Oriel: could not save settings: \(error)")
        }
    }

    func screenSetting(for display: DisplayInfo) -> ScreenSetting {
        settings.effectiveScreen(for: display.uuid)
    }

    func setScreenLayout(_ layout: LayoutKind, for display: DisplayInfo) {
        update { s in
            var current = s.effectiveScreen(for: display.uuid)
            current.layout = layout
            current.capacity = min(current.capacity, max(1, layout.maxTiles(on: display)))
            s.screenOverrides[display.uuid] = current
        }
    }

    func setScreenCapacity(_ capacity: Int, for display: DisplayInfo) {
        update { s in
            var current = s.effectiveScreen(for: display.uuid)
            current.capacity = max(1, min(capacity, current.layout.maxTiles(on: display)))
            s.screenOverrides[display.uuid] = current
        }
    }

    func setScreenRatio(_ ratio: Double, for display: DisplayInfo) {
        update { s in
            var current = s.effectiveScreen(for: display.uuid)
            current.ratio = ratio
            s.screenOverrides[display.uuid] = current
        }
    }

    func clearOverride(for display: DisplayInfo) {
        update { s in
            s.screenOverrides.removeValue(forKey: display.uuid)
        }
    }

    func addAppRule(bundleID: String, appName: String, mode: AppRuleMode = .float) {
        update { s in
            if let index = s.appRules.firstIndex(where: { $0.bundleID == bundleID && $0.titlePrefix == nil }) {
                s.appRules[index].mode = mode
                s.appRules[index].appName = appName
            } else {
                s.appRules.append(AppRule(bundleID: bundleID, appName: appName, mode: mode))
            }
        }
    }

    func removeAppRule(id: UUID) {
        update { s in s.appRules.removeAll { $0.id == id } }
    }

    func rule(for bundleID: String, title: String) -> AppRule? {
        settings.appRules.first { rule in
            guard rule.bundleID == bundleID, rule.mode == .float else { return false }
            if let prefix = rule.titlePrefix, !prefix.isEmpty {
                return title.localizedCaseInsensitiveContains(prefix)
            }
            return true
        }
    }
}
