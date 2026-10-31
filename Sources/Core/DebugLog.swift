import Foundation
import os

/// Opt-in diagnostics. Nothing is written unless Oriel is launched with
/// `--debug` or `ORIEL_DEBUG=1`, so normal builds stay quiet and private.
enum DebugLog {
    static let isEnabled: Bool = {
        CommandLine.arguments.contains("--debug") ||
        ProcessInfo.processInfo.environment["ORIEL_DEBUG"] == "1"
    }()

    private static let logger = Logger(subsystem: "app.oriel.mac", category: "diagnostics")
    private static let queue = DispatchQueue(label: "app.oriel.debuglog")
    private static let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("oriel-debug.log")

    static func write(_ message: String) {
        guard isEnabled else { return }
        logger.info("\(message, privacy: .public)")
        queue.async {
            let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    static func reset() {
        guard isEnabled else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
