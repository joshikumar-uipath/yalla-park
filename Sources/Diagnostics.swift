import Foundation
import OSLog
import SwiftUI

/// Phase-1 troubleshooting black box (remote testers can't hand you their
/// phone). Every significant event is one JSON line in a rotating on-device
/// file, mirrored to OSLog. NOTHING leaves the phone until the owner taps
/// Share in Settings → Diagnostics.
///
/// Privacy contract: no plate, no phone numbers, no continuous location.
/// Zone-DETECTION events carry coordinates rounded to ~10 m (4 decimals) —
/// the minimum needed to re-run point-in-polygon and debug a wrong zone.
enum Diag {
    private static let queue = DispatchQueue(label: "diag.log", qos: .utility)
    private static let logger = Logger(subsystem: "com.avjoshi.dxbpark", category: "diag")
    /// Rotate when the live file passes this; one older generation is kept.
    private static let maxBytes = 1_500_000

    static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "diagnostics.jsonl")
    }
    private static var oldFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "diagnostics.old.jsonl")
    }

    /// Log one event. Values must be JSON-encodable primitives.
    static func log(_ event: String, _ fields: [String: Any] = [:]) {
        let stamp = ISO8601DateFormatter().string(from: .now)
        var record: [String: Any] = ["t": stamp, "e": event]
        record["b"] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        for (key, value) in fields { record[key] = value }
        logger.info("\(event, privacy: .public) \(String(describing: fields), privacy: .public)")
        queue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: record),
                  let line = String(data: data, encoding: .utf8) else { return }
            append(line: line + "\n")
        }
    }

    /// Round to ~10 m — enough to reproduce polygon lookups, not a track.
    static func coarse(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }

    private static func append(line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: .applicationSupportDirectory,
                                     withIntermediateDirectories: true)
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
        if let size = try? manager.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
           size > maxBytes {
            try? manager.removeItem(at: oldFileURL)
            try? manager.moveItem(at: fileURL, to: oldFileURL)
        }
    }

    /// Newest-first tail for the in-app viewer.
    static func recentLines(limit: Int = 200) -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").suffix(limit).reversed().map(String.init)
    }

    static func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: oldFileURL)
        }
    }
}

// MARK: - Settings → Diagnostics

/// The black box, readable and sharable by its owner. The file leaves the
/// phone only through the Share button below.
struct DiagnosticsView: View {
    @State private var lines: [String] = []

    var body: some View {
        List {
            Section {
                ShareLink(item: Diag.fileURL) {
                    Label("Share diagnostics file", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    Diag.clear()
                    lines = []
                } label: {
                    Label("Clear log", systemImage: "trash")
                }
            } footer: {
                Text("Everything here stays on this phone until you share it. No plate, no continuous location — zone-detection entries carry ~10 m coordinates so wrong-zone bugs can be reproduced.")
            }
            Section("Recent events — newest first") {
                if lines.isEmpty {
                    Text("Nothing logged yet.")
                        .foregroundStyle(Theme.labelTertiary)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.labelSecondary)
                        .lineLimit(4)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .onAppear { lines = Diag.recentLines() }
        .refreshable { lines = Diag.recentLines() }
    }
}
