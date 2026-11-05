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

    /// Loads a layout, preferring a file that matches the physical keyboard standard.
    ///
    /// A locale can ship several physical variants (for Japanese: ANSI and JIS).
    /// The variant file is `\(locale)_\(os)_\(standard).json`; the plain
    /// `\(locale)_\(os).json` is the fallback when no variant exists.
    static func load(
        locale: KeyboardLocale,
        targetOS: TargetOS,
        physicalStandard: KeyboardLocale.PhysicalStandard? = nil
    ) throws -> KeyboardLayoutDefinition {
        let candidates = filenames(locale: locale, targetOS: targetOS, physicalStandard: physicalStandard)
        var fileURL: URL?
        for filename in candidates {
            if let url = resolveURL(filename: filename) {
                fileURL = url
                break
            }
        }

        guard let url = fileURL else {
            throw KeyboardLayoutError.fileNotFound(candidates.last ?? "")
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let jsonLayout = try decoder.decode(JSONKeyboardLayout.self, from: data)

        let layout = try convert(jsonLayout)

        // Validate layout
        let validation = KeyboardLayoutValidator.validate(layout)
        if !validation.isValid {
            let msg = validation.errors.map(\.localizedDescription).joined(separator: "; ")
            throw KeyboardLayoutError.invalidFormat(msg)
        }
        #if DEBUG
        for w in validation.warnings {
            print("⚠️ Layout warning: \(w)")
        }
        #endif

        return layout
    }

    private static func filenames(
        locale: KeyboardLocale,
        targetOS: TargetOS,
        physicalStandard: KeyboardLocale.PhysicalStandard?
    ) -> [String] {
        let base = "\(locale.rawValue.lowercased())_\(targetOS.rawValue.lowercased())"
        let standard = physicalStandard ?? locale.physicalStandard
        return ["\(base)_\(standard.rawValue.lowercased()).json", "\(base).json"]
    }

    private static func resolveURL(filename: String) -> URL? {
        // 1. Try override directory first (for testing - takes priority)
        if let override = layoutsDirectoryOverride {
            let url = URL(fileURLWithPath: override).appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // 2. Try bundle resource
        if let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "KeyboardLayouts") {
            return url
        }
        if let url = Bundle.main.url(forResource: filename, withExtension: nil) {
            return url
        }

        // 3. Try filesystem relative to project root
        let root = findProjectRoot()
        let url = URL(fileURLWithPath: root)
            .appendingPathComponent("Resources/KeyboardLayouts/")
            .appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
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

        // A physical keyboard cannot have two keys in the same slot. Catch
        // authoring mistakes such as a missing Y key leaving a duplicate
        // column, which otherwise silently shifts a row's layout.
        for (rowIndex, entries) in tempRows.enumerated() {
            var seen: [Int: String] = [:]
            for (column, def) in entries {
                if let existing = seen[column] {
                    throw KeyboardLayoutError.invalidFormat(
                        "Duplicate position (row \(rowIndex), column \(column)): \(existing), \(def.keyName)"
                    )
                }
                seen[column] = def.keyName
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
        // Parse deadKey field from JSON
        let deadKey: DeadKey?
        if let deadKeyStr = json.deadKey {
            deadKey = DeadKey(rawValue: deadKeyStr)
        } else {
            deadKey = nil
        }
        return KeyDefinition(
            keyName: json.keyName,
            label: json.label,
            shiftLabel: json.shiftLabel,
            altGrLabel: json.altGrLabel,
            keyCode: json.keyCode,
            hidUsageID: uid,
            keyType: type,
            deadKey: deadKey,
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
    let deadKey: String?
}

/// Error types for layout loading.
enum KeyboardLayoutError: Error {
    case fileNotFound(String)
    case invalidFormat(String)
}
