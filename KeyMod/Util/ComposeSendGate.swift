import Foundation

/// Send-gate rules mirroring Android ImeComposeSendGate.
enum ComposeSendGate {
    static let longTextWarningThreshold = 300

    struct Assessment {
        let hardBlock: HardBlockReason?
        let warningInfo: WarningInfo?

        var canSend: Bool { hardBlock == nil }
    }

    enum HardBlockReason {
        case noConnection
        case emptyText
    }

    struct WarningInfo: Identifiable {
        let hasNonAscii: Bool
        let hasLengthRisk: Bool
        let charCount: Int

        var id: String { "\(hasNonAscii)-\(hasLengthRisk)-\(charCount)" }
    }

    static func assess(isConnected: Bool, text: String) -> Assessment {
        if !isConnected {
            return Assessment(hardBlock: .noConnection, warningInfo: nil)
        }
        if text.isEmpty {
            return Assessment(hardBlock: .emptyText, warningInfo: nil)
        }
        return Assessment(hardBlock: nil, warningInfo: buildWarningInfo(text))
    }

    private static func buildWarningInfo(_ text: String) -> WarningInfo? {
        let hasNonAscii = text.unicodeScalars.contains { $0.value > 127 }
        let hasLengthRisk = text.count >= longTextWarningThreshold
        guard hasNonAscii || hasLengthRisk else { return nil }
        return WarningInfo(hasNonAscii: hasNonAscii, hasLengthRisk: hasLengthRisk, charCount: text.count)
    }

    /// Preview text with non-ASCII code points dropped (what the receiver actually gets in ASCII mode).
    static func asciiPreview(of text: String) -> String {
        String(text.unicodeScalars.filter { $0.value <= 127 })
    }
}
