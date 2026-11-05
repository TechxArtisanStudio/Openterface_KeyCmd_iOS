//
//  KeyboardLayoutDefinition.swift
//  KeyMod
//
//  Data structures for keyboard layout definitions.
//  Supports ANSI, ISO, and JIS physical standards.
//  Uses KeyType from KeyType.swift (in MultiTouch module).
//

import Foundation
import SwiftUI

// MARK: - Layout Padding (Codable/Equatable replacement for EdgeInsets)

/// Layout padding - replacement for EdgeInsets to support Codable/Equatable
struct LayoutPadding: Codable, Equatable, Hashable {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat

    init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// Convert to SwiftUI EdgeInsets
    var edgeInsets: EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    /// Create from SwiftUI EdgeInsets
    static func from(_ insets: EdgeInsets) -> LayoutPadding {
        LayoutPadding(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing)
    }

    /// Default padding
    static let `default` = LayoutPadding(top: 8, leading: 8, bottom: 0, trailing: 0)
}

// MARK: - Key Definition

/// Complete definition for a single key
struct KeyDefinition: Codable, Equatable, Hashable {
    let keyName: String           // Internal identifier, e.g. "q", "1", "Shift"
    let label: String             // Primary label displayed on key, e.g. "Q", "1", "Shift"
    let shiftLabel: String?       // Label shown when Shift is pressed, e.g. "!", "@"
    let altGrLabel: String?       // Label shown when AltGr/Option is pressed (needed for European layouts)
    let keyCode: String           // Key name for HID key code lookup
    let hidUsageID: HIDUsageID    // USB HID Usage ID for this key
    let keyType: KeyType          // Key type (from KeyType.swift)
    let deadKey: DeadKey?         // Dead key type (if this key is a dead key)
    let widthMultiplier: CGFloat? // Width multiplier (relative to standard key), nil means auto
    let heightMultiplier: CGFloat? // Height multiplier (relative to standard row), nil means auto

    init(keyName: String,
         label: String,
         shiftLabel: String? = nil,
         altGrLabel: String? = nil,
         keyCode: String? = nil,
         hidUsageID: HIDUsageID,
         keyType: KeyType = .regular,
         deadKey: DeadKey? = nil,
         widthMultiplier: CGFloat? = nil,
         heightMultiplier: CGFloat? = nil) {
        self.keyName = keyName
        self.label = label
        self.shiftLabel = shiftLabel
        self.altGrLabel = altGrLabel
        self.keyCode = keyCode ?? keyName
        self.hidUsageID = hidUsageID
        self.keyType = keyType
        self.deadKey = deadKey
        self.widthMultiplier = widthMultiplier
        self.heightMultiplier = heightMultiplier
    }

    /// Gets the HID Usage ID's raw value
    var hidUsageValue: UInt8 {
        hidUsageID.rawValue
    }
}

/// A single row of key definitions
typealias KeyRow = [KeyDefinition]

// MARK: - Layout Metadata

/// Layout metadata
struct LayoutMetadata: Codable, Equatable, Hashable {
    let name: String                    // Layout name, e.g. "US QWERTY"
    let description: String             // Short description
    let rowHeights: [CGFloat]?          // Relative height ratios for each row
    let keySpacing: CGFloat             // Key spacing
    let rowSpacing: CGFloat             // Row spacing
    let padding: LayoutPadding          // Inner padding
    let fixedKeyWidths: [String: CGFloat] // Fixed width keys
    let physicalStandard: KeyboardLocale.PhysicalStandard // Physical standard
    let hasAltGr: Bool                  // Whether AltGr key is supported (needed for European layouts)

    init(name: String = "",
         description: String = "",
         rowHeights: [CGFloat]? = nil,
         keySpacing: CGFloat = 3,
         rowSpacing: CGFloat = 6,
         padding: LayoutPadding = .default,
         fixedKeyWidths: [String: CGFloat] = ["Space": 200],
         physicalStandard: KeyboardLocale.PhysicalStandard = .ansi,
         hasAltGr: Bool = false) {
        self.name = name
        self.description = description
        self.rowHeights = rowHeights
        self.keySpacing = keySpacing
        self.rowSpacing = rowSpacing
        self.padding = padding
        self.fixedKeyWidths = fixedKeyWidths
        self.physicalStandard = physicalStandard
        self.hasAltGr = hasAltGr
    }
}

// MARK: - Keyboard Layout Definition

/// Complete keyboard layout definition
struct KeyboardLayoutDefinition: Codable, Equatable, Hashable {
    let locale: KeyboardLocale
    let targetOS: TargetOS
    let rows: [KeyRow]
    let metadata: LayoutMetadata

    /// Cache identifier for fast lookup
    var layoutCacheKey: String {
        "\(targetOS.rawValue)_\(locale.rawValue)"
    }

    /// Convert to KeyboardLayoutDescription used by touch layer
    func toLayoutDescription(containerSize: CGSize) -> KeyboardLayoutDescription {
        let stringRows = rows.map { $0.map { $0.keyName } }

        // Convert ratio-based row heights to actual pixel values.
        // Metadata stores rowHeights as relative ratios (e.g. [0.1, 0.1, 0.2, ...]);
        // the touch layer's KeyFrameRegistry treats them as absolute pixel values,
        // so we must scale them to match the container height.
        let convertedRowHeights: [CGFloat]
        if let ratios = metadata.rowHeights, !ratios.isEmpty {
            let contentHeight = containerSize.height - metadata.padding.top - metadata.padding.bottom
            let totalRowSpacing = CGFloat(max(0, rows.count - 1)) * metadata.rowSpacing
            let availableHeight = max(0, contentHeight - totalRowSpacing)
            let totalRatio = ratios.reduce(0, +)
            if totalRatio > 0 {
                convertedRowHeights = ratios.map { ($0 / totalRatio) * availableHeight }
            } else {
                convertedRowHeights = []
            }
        } else {
            convertedRowHeights = []
        }

        return KeyboardLayoutDescription(
            rows: stringRows,
            containerSize: containerSize,
            rowSpacing: metadata.rowSpacing,
            keySpacing: metadata.keySpacing,
            padding: metadata.padding.edgeInsets,
            fixedRowHeights: convertedRowHeights,
            fixedKeyWidths: metadata.fixedKeyWidths
        )
    }

    /// Get key type mapping (used by touch layer)
    func keyTypeResolver() -> (String) -> KeyType {
        let typeMap = Dictionary(rows.flatMap { $0 }.map { ($0.keyName, $0.keyType) }, uniquingKeysWith: { first, _ in first })
        return { keyName in
            typeMap[keyName] ?? .regular
        }
    }

    /// Get key definition lookup
    func keyDefinition(for keyName: String) -> KeyDefinition? {
        rows.flatMap { $0 }.first { $0.keyName == keyName }
    }

    /// Get flattened array of all key definitions
    var allKeys: [KeyDefinition] {
        rows.flatMap { $0 }
    }
}

// MARK: - Builder Helpers

/// Layout builder helper extensions
extension KeyDefinition {
    /// Create a standard character key
    static func key(_ name: String, _ label: String, shift: String? = nil, altGr: String? = nil,
                    keyCode: String? = nil, hid: HIDUsageID = .keyboardA, type: KeyType = .regular,
                    deadKey: DeadKey? = nil, width: CGFloat? = nil, height: CGFloat? = nil) -> KeyDefinition {
        KeyDefinition(keyName: name, label: label, shiftLabel: shift, altGrLabel: altGr,
                      keyCode: keyCode ?? name, hidUsageID: hid, keyType: type, deadKey: deadKey,
                      widthMultiplier: width, heightMultiplier: height)
    }

    /// Create a modifier key
    static func mod(_ name: String, label: String? = nil, keyCode: String? = nil, hid: HIDUsageID = .keyboardA, width: CGFloat? = nil, height: CGFloat? = nil) -> KeyDefinition {
        KeyDefinition(keyName: name, label: label ?? name, shiftLabel: nil, altGrLabel: nil,
                      keyCode: keyCode ?? name, hidUsageID: hid, keyType: .modifier, deadKey: nil,
                      widthMultiplier: width, heightMultiplier: height)
    }

    /// Create a special key
    static func special(_ name: String, label: String? = nil, keyCode: String? = nil, hid: HIDUsageID = .keyboardA, width: CGFloat? = nil, height: CGFloat? = nil) -> KeyDefinition {
        KeyDefinition(keyName: name, label: label ?? name, shiftLabel: nil, altGrLabel: nil,
                      keyCode: keyCode ?? name, hidUsageID: hid, keyType: .special, deadKey: nil,
                      widthMultiplier: width, heightMultiplier: height)
    }

    /// Create a Japanese special key
    static func jpSpecial(_ name: String, label: String, hid: HIDUsageID = .keyboardA, width: CGFloat? = nil) -> KeyDefinition {
        KeyDefinition(keyName: name, label: label, shiftLabel: nil, altGrLabel: nil,
                      keyCode: name, hidUsageID: hid, keyType: .japaneseSpecial, deadKey: nil,
                      widthMultiplier: width)
    }
}

// MARK: - Layout Row Types

/// Layout row type enum for applying regional variants
enum LayoutRowType: String, CaseIterable {
    case functionRow  // F1-F12 row
    case numberRow    // Number row
    case row3         // QWERTY/AZERTY first row
    case row4         // ASDF second row
    case row5         // ZXCV third row
    case bottomRow    // Bottom modifier row
}

// MARK: - Preview Helper

#if DEBUG
extension KeyboardLayoutDefinition {
    /// Generate simplified layout description for preview
    var previewDescription: String {
        let rowStrings = rows.map { row in
            row.map { $0.label }.joined(separator: " ")
        }
        return "\(metadata.name)\n\(rowStrings.joined(separator: "\n"))"
    }
}
#endif