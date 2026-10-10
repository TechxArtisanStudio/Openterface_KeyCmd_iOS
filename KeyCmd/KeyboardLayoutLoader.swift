import Foundation
import SwiftUI

/// Loads keyboard layout definitions from JSON files in the Resources/KeyboardLayouts directory.
/// The layout files follow the structure defined in `docs/superpowers/specs/keyboard-layout-json-schema.md`.
///
/// **Usage**: `KeyboardLayoutLoader.load(locale: .us, targetOS: .windows)`
///
/// It throws `KeyboardLayoutError` if the file cannot be found or the data is malformed.
struct KeyboardLayoutLoader {

    /// Optional override for the layouts directory (used in tests).
    static var layoutsDirectoryOverride: String?

    static func load(locale: KeyboardLocale, targetOS: TargetOS) throws -> KeyboardLayoutDefinition {
        let filename = "\(locale.rawValue.lowercased())_\(targetOS.rawValue.lowercased()).json"
        var fileURL: URL?

        // 1. Try bundle resource
        if let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "KeyboardLayouts") {
            fileURL = url
        } else if let url = Bundle.main.url(forResource: filename, withExtension: nil) {
            fileURL = url
        }

        // 2. Try override directory (for testing)
        if fileURL == nil, let override = layoutsDirectoryOverride {
            let url = URL(fileURLWithPath: override).appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                fileURL = url
            }
        }

        // 3. Try filesystem relative to project root
        if fileURL == nil {
            let root = findProjectRoot()
            let url = URL(fileURLWithPath: root).appendingPathComponent("Resources/KeyboardLayouts/").appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                fileURL = url
            }
        }

        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw KeyboardLayoutError.fileNotFound(filename)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let jsonLayout = try decoder.decode(JSONKeyboardLayout.self, from: data)

        return try convert(jsonLayout)
    }

    /// Find project root by walking up from current directory or using environment variable
    private static func findProjectRoot() -> String {
        // 1. Check environment variable (useful for testing/CI)
        if let envPath = ProcessInfo.processInfo.environment["KEYCMD_PROJECT_ROOT"] {
            let layoutsPath = (envPath as NSString).appendingPathComponent("Resources/KeyboardLayouts")
            if FileManager.default.fileExists(atPath: layoutsPath) {
                return envPath
            }
        }

        // 2. Walk up from current directory
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("Resources/KeyboardLayouts")) {
                return dir
            }
            dir = (dir as NSString).deletingLastPathComponent
        }

        // 3. Fallback to current directory
        return FileManager.default.currentDirectoryPath
    }

    private static func convert(_ json: JSONKeyboardLayout) throws -> KeyboardLayoutDefinition {
        // Parse locale and targetOS from JSON
        guard let locale = KeyboardLocale.allCases.first(where: { $0.rawValue.lowercased() == json.locale.lowercased() }) else {
            throw KeyboardLayoutError.invalidFormat("Invalid locale: \(json.locale)")
        }
        guard let targetOS = TargetOS.allCases.first(where: { $0.rawValue.lowercased() == json.targetOS.lowercased() }) else {
            throw KeyboardLayoutError.invalidFormat("Invalid targetOS: \(json.targetOS)")
        }

        var tempRows: [[(Int, KeyDefinition)]] = []
        let maxRowIndex = (json.keys.map { $0.row }.max() ?? 0) + 1
        tempRows = Array(repeating: [], count: maxRowIndex)

        for jsonKey in json.keys {
            let def = try keyDefinition(from: jsonKey)
            if jsonKey.row < tempRows.count {
                tempRows[jsonKey.row].append((jsonKey.column, def))
            }
        }

        let rows: [KeyRow] = tempRows.map { $0.sorted { $0.0 < $1.0 }.map { $0.1 } }

        let metadata = LayoutMetadata(
            name: json.metadata.name,
            description: json.metadata.description ?? "",
            rowHeights: json.metadata.rowHeights,
            keySpacing: json.metadata.keySpacing ?? 3,
            rowSpacing: json.metadata.rowSpacing ?? 6,
            padding: json.metadata.padding ?? .default,
            fixedKeyWidths: json.metadata.fixedKeyWidths ?? [:],
            physicalStandard: json.metadata.physicalStandard,
            hasAltGr: json.metadata.hasAltGr ?? false
        )

        return KeyboardLayoutDefinition(
            locale: locale,
            targetOS: targetOS,
            rows: rows,
            metadata: metadata
        )
    }

    private static func keyDefinition(from json: JSONKeyDefinition) throws -> KeyDefinition {
        let uid: HIDUsageID
        if let raw = HIDUsageID(rawValue: json.hidUsageID) {
            uid = raw
        } else {
            throw KeyboardLayoutError.invalidFormat("Invalid HID usage ID: \(json.hidUsageID)")
        }
        let type: KeyType
        if let raw = json.keyType,
           let t = KeyType(rawValue: raw) {
            type = t
        } else {
            type = .regular
        }
        return KeyDefinition(
            keyName: json.keyName,
            label: json.label,
            shiftLabel: json.shiftLabel,
            altGrLabel: json.altGrLabel,
            keyCode: json.keyCode,
            hidUsageID: uid,
            keyType: type,
            widthMultiplier: json.width,
            heightMultiplier: json.height
        )
    }
}

// MARK: - JSON Structures matching the schema
private struct JSONKeyboardLayout: Decodable {
    let locale: String
    let targetOS: String
    let metadata: JSONLayoutMetadata
    let keys: [JSONKeyDefinition]
}

private struct JSONLayoutMetadata: Decodable {
    let name: String
    let description: String?
    let rowHeights: [CGFloat]?
    let keySpacing: CGFloat?
    let rowSpacing: CGFloat?
    let padding: LayoutPadding?
    let fixedKeyWidths: [String: CGFloat]?
    let physicalStandard: KeyboardLocale.PhysicalStandard
    let hasAltGr: Bool?
}

private struct JSONKeyDefinition: Decodable {
    let hidUsageID: UInt8
    let keyName: String
    let label: String
    let shiftLabel: String?
    let altGrLabel: String?
    let keyCode: String?
    let keyType: String?
    let width: CGFloat?
    let height: CGFloat?
    let row: Int
    let column: Int
}

/// Error types for layout loading.
enum KeyboardLayoutError: Error {
    case fileNotFound(String)
    case invalidFormat(String)
}
