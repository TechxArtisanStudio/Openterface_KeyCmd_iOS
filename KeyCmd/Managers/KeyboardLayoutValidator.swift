// KeyCmd/Managers/KeyboardLayoutValidator.swift
import Foundation

/// 验证键盘布局 JSON 的正确性
struct KeyboardLayoutValidator {

    struct ValidationResult {
        let isValid: Bool
        let errors: [ValidationError]
        let warnings: [ValidationWarning]
    }

    enum ValidationError: Error, LocalizedError {
        case duplicateHIDUsageID(HIDUsageID, [KeyDefinition])
        case duplicatePosition(row: Int, column: Int, keys: [KeyDefinition])
        case altGrWithoutHasAltGr(keyName: String)
        case modifierKeyInvalidHID(keyName: String, hid: HIDUsageID)
        case missingRequiredKeys([String])

        var errorDescription: String? {
            switch self {
            case .duplicateHIDUsageID(let hid, let keys):
                return "Duplicate HID Usage ID 0x\(String(hid.rawValue, radix: 16)): \(keys.map(\.keyName))"
            case .duplicatePosition(let row, let column, let keys):
                return "Duplicate position (\(row), \(column)): \(keys.map(\.keyName))"
            case .altGrWithoutHasAltGr(let keyName):
                return "Key '\(keyName)' has altGrLabel but metadata.hasAltGr=false"
            case .modifierKeyInvalidHID(let keyName, let hid):
                return "Modifier key '\(keyName)' has HID 0x\(String(hid.rawValue, radix: 16)) (must be 0xE0-0xE7)"
            case .missingRequiredKeys(let names):
                return "Missing required keys: \(names.joined(separator: ", "))"
            }
        }
    }

    enum ValidationWarning {
        case keyWithoutLabel(keyName: String)
        case unusedHIDUsageID(HIDUsageID)
        case deadKeySymbolMismatch(keyName: String, deadKey: DeadKey, label: String)
    }

    static func validate(_ layout: KeyboardLayoutDefinition) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []

        let allKeys = layout.allKeys

        // 1. HID Usage ID 唯一性
        let hidGroups = Dictionary(grouping: allKeys, by: { $0.hidUsageID })
        for (hid, keys) in hidGroups where keys.count > 1 {
            errors.append(.duplicateHIDUsageID(hid, keys))
        }

        // 2. 同一行内 keyName 唯一性
        // 精确的 (row, column) 冲突由 KeyboardLayoutLoader 在解析时直接拒绝。
        for (rowIndex, row) in layout.rows.enumerated() {
            let nameGroups = Dictionary(grouping: row, by: { $0.keyName })
            for (name, keys) in nameGroups where keys.count > 1 {
                errors.append(.duplicatePosition(row: rowIndex, column: 0, keys: keys))
            }
        }

        // 3. 死键符号一致性 (降级为警告 - 很多布局的标签显示的是键帽字符而非组合符号)
        for key in allKeys {
            if let deadKey = key.deadKey {
                if key.label.first?.lowercased() != deadKey.symbol.lowercased() {
                    warnings.append(.deadKeySymbolMismatch(keyName: key.keyName, deadKey: deadKey, label: key.label))
                }
            }
        }

        // 4. AltGr 一致性
        if !layout.metadata.hasAltGr {
            for key in allKeys where key.altGrLabel != nil {
                errors.append(.altGrWithoutHasAltGr(keyName: key.keyName))
            }
        }

        // 5. 修饰键 HID 范围检查
        for key in allKeys where key.keyType == .modifier {
            if !(0xE0...0xE7).contains(key.hidUsageID.rawValue) {
                errors.append(.modifierKeyInvalidHID(keyName: key.keyName, hid: key.hidUsageID))
            }
        }

        // 6. 必需键检查
        let requiredKeys = ["Esc", "Enter", "Space", "Tab", "Backspace", "LeftShift", "RightShift"]
        let missing = requiredKeys.filter { name in
            !allKeys.contains { $0.keyName == name }
        }
        if !missing.isEmpty {
            errors.append(.missingRequiredKeys(missing))
        }

        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
}
