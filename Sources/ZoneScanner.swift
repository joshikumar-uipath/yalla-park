import SwiftUI
import VisionKit

/// Task 5 — read the zone code straight off the Parkin sign, on-device.
/// VisionKit Live Text; no photo is stored, nothing leaves the phone.

enum ZoneScan {
    /// Device-gated: needs A12+ and a camera — false in the simulator.
    @MainActor
    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// Extract plausible Parkin zone codes (3–4 digits + letter, e.g. 382F)
    /// from recognized text. Pure and unit-tested.
    static func candidates(in strings: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in strings {
            let tokens = raw.uppercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            for token in tokens {
                let text = String(token)
                // 1-2 letter suffixes: 318C, 248W, and Al Barsha's 373CP (field 2026-08-11).
                guard text.range(of: #"^\d{3,4}[A-Z]{1,2}$"#, options: .regularExpression) != nil,
                      seen.insert(text).inserted else { continue }
                out.append(text)
            }
        }
        return out
    }
}

/// Camera sheet: live text scanning with tappable zone-code candidates.
struct ZoneScannerSheet: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [String] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            ZoneScannerRepresentable { strings in
                let found = ZoneScan.candidates(in: strings)
                if !found.isEmpty {
                    // Keep the most recent handful, newest first.
                    candidates = Array((found + candidates).uniqued().prefix(4))
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(candidates.isEmpty
                     ? "Point at the blue/orange parking sign"
                     : "Tap your zone")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(.black.opacity(0.55), in: Capsule())

                if !candidates.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(candidates, id: \.self) { code in
                            Button {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                onPick(code)
                                dismiss()
                            } label: {
                                Text(code)
                                    .font(.system(size: 20, weight: .bold))
                                    .monospacedDigit()
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 18)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(Theme.labelPrimary)
                            }
                        }
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 22)
                        .background(.black.opacity(0.55), in: Capsule())
                }
            }
            .padding(.bottom, 28)
        }
    }
}

private struct ZoneScannerRepresentable: UIViewControllerRepresentable {
    let onRecognized: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onRecognized: onRecognized) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRecognized: ([String]) -> Void
        init(onRecognized: @escaping ([String]) -> Void) { self.onRecognized = onRecognized }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(allItems)
        }

        private func report(_ items: [RecognizedItem]) {
            let strings: [String] = items.compactMap {
                if case .text(let text) = $0 { return text.transcript }
                return nil
            }
            if !strings.isEmpty { onRecognized(strings) }
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
