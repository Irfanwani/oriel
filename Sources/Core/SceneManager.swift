import AppKit

@MainActor
final class SceneManager {
    private let prefs = Preferences.shared
    private let manager = WindowManager.shared
    private let displays = DisplayManager.shared

    var onStatus: ((String, String) -> Void)?

    func saveCurrentScene(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var entries: [SceneWindow] = []
        var order = 0

        for display in displays.displays {
            for window in manager.orderedWindowsForDisplay(display) {
                entries.append(SceneWindow(
                    bundleID: window.bundleID,
                    appName: window.appName,
                    displayUUID: display.uuid,
                    order: order,
                    floating: false
                ))
                order += 1
            }
            for window in manager.windows where window.displayUUID == display.uuid && window.isFloating {
                entries.append(SceneWindow(
                    bundleID: window.bundleID,
                    appName: window.appName,
                    displayUUID: display.uuid,
                    order: order,
                    floating: true,
                    frame: window.frame
                ))
                order += 1
            }
        }

        // Save the effective setting for every display, not only displays that
        // already had an override. A scene should restore the same geometry even
        // if the global layout changes later.
        var overrides: [String: ScreenSetting] = [:]
        for display in displays.displays {
            overrides[display.uuid] = prefs.screenSetting(for: display)
        }
        let scene = SavedScene(name: name, windows: entries, screenOverrides: overrides)

        prefs.update { settings in
            if let index = settings.scenes.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                settings.scenes[index] = scene
            } else {
                settings.scenes.append(scene)
            }
        }
        onStatus?("Scene saved", "\(name) · \(entries.count) window\(entries.count == 1 ? "" : "s")")
    }

    func delete(_ scene: SavedScene) {
        prefs.update { settings in
            settings.scenes.removeAll { $0.id == scene.id }
        }
    }

    func restore(_ scene: SavedScene) {
        guard AX.isTrusted else {
            onStatus?("Accessibility needed", "Grant access to restore scenes")
            return
        }

        for (uuid, setting) in scene.screenOverrides where displays.displays.contains(where: { $0.uuid == uuid }) {
            prefs.update { s in s.screenOverrides[uuid] = setting }
        }

        let wanted = Set(scene.windows.map(\.bundleID))
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let missing = wanted.subtracting(running)

        for bundleID in missing {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        }

        onStatus?("Restoring scene", scene.name)

        Task { @MainActor [weak self] in
            guard let self else { return }
            var covered = false
            for attempt in 0..<15 {
                try? await Task.sleep(nanoseconds: 380_000_000)
                self.manager.reconcile(force: false)
                self.manager.applyScene(scene)
                if attempt >= 2, attempt % 3 == 0 {
                    self.manager.reconcile(force: true)
                }
                if attempt >= 2, self.manager.sceneIsCovered(scene) {
                    covered = true
                    break
                }
            }
            self.manager.reconcile(force: true)
            self.onStatus?(covered ? "Scene restored" : "Scene partially restored", scene.name)
        }
    }
}
