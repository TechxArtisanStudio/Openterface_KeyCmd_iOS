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

/// 布局内边距 - 替代 EdgeInsets 以支持 Codable/Equatable
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

    /// 转换为 SwiftUI EdgeInsets
    var edgeInsets: EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    /// 从 SwiftUI EdgeInsets 创建
    static func from(_ insets: EdgeInsets) -> LayoutPadding {
        LayoutPadding(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing)
    }

    /// 默认内边距
    static let `default` = LayoutPadding(top: 8, leading: 8, bottom: 0, trailing: 0)
}

// MARK: - Key Definition

/// 单个按键的完整定义
struct KeyDefinition: Codable, Equatable, Hashable {
    let keyName: String           // 内部标识符，如 "q", "1", "Shift"
    let label: String             // 按键上显示的主标签，如 "Q", "1", "Shift"
    let shiftLabel: String?       // Shift按下时显示的标签，如 "!", "@"
    let altGrLabel: String?       // AltGr/Option按下时显示的标签（欧洲布局需要）
    let keyCode: String           // HID键码查找用的键名
    let keyType: KeyType          // 按键类型（来自 KeyType.swift）
    let widthMultiplier: CGFloat? // 宽度倍数（相对标准键），nil表示自动
    let heightMultiplier: CGFloat? // 高度倍数（相对标准行），nil表示自动

    init(keyName: String,
         label: String,
         shiftLabel: String? = nil,
         altGrLabel: String? = nil,
         keyCode: String? = nil,
         keyType: KeyType = .regular,
         widthMultiplier: CGFloat? = nil,
         heightMultiplier: CGFloat? = nil) {
        self.keyName = keyName
        self.label = label
        self.shiftLabel = shiftLabel
        self.altGrLabel = altGrLabel
        self.keyCode = keyCode ?? keyName
        self.keyType = keyType
        self.widthMultiplier = widthMultiplier
        self.heightMultiplier = heightMultiplier
    }
}

/// 一行按键定义
typealias KeyRow = [KeyDefinition]

// MARK: - Layout Metadata

/// 布局元数据
struct LayoutMetadata: Codable, Equatable, Hashable {
    let name: String                    // 布局名称，如 "US QWERTY"
    let description: String             // 简短描述
    let rowHeights: [CGFloat]?          // 各行相对高度比例
    let keySpacing: CGFloat             // 按键间距
    let rowSpacing: CGFloat             // 行间距
    let padding: LayoutPadding          // 内边距
    let fixedKeyWidths: [String: CGFloat] // 固定宽度的按键
    let physicalStandard: KeyboardLocale.PhysicalStandard // 物理标准
    let hasAltGr: Bool                  // 是否支持 AltGr 键（欧洲布局需要）

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

/// 完整键盘布局定义
struct KeyboardLayoutDefinition: Codable, Equatable, Hashable {
    let locale: KeyboardLocale
    let targetOS: TargetOS
    let rows: [KeyRow]
    let metadata: LayoutMetadata

    /// 缓存标识符，用于快速查找
    var layoutCacheKey: String {
        "\(targetOS.rawValue)_\(locale.rawValue)"
    }

    /// 转换为触摸层使用的 KeyboardLayoutDescription
    func toLayoutDescription(containerSize: CGSize) -> KeyboardLayoutDescription {
        let stringRows = rows.map { $0.map { $0.keyName } }
        let fixedRowHeights = metadata.rowHeights ?? []

        return KeyboardLayoutDescription(
            rows: stringRows,
            containerSize: containerSize,
            rowSpacing: metadata.rowSpacing,
            keySpacing: metadata.keySpacing,
            padding: metadata.padding.edgeInsets,
            fixedRowHeights: fixedRowHeights,
            fixedKeyWidths: metadata.fixedKeyWidths
        )
    }

    /// 获取按键类型映射（用于触摸层）
    func keyTypeResolver() -> (String) -> KeyType {
        let typeMap = Dictionary(uniqueKeysWithValues: rows.flatMap { $0 }.map { ($0.keyName, $0.keyType) })
        return { keyName in
            typeMap[keyName] ?? .regular
        }
    }

    /// 获取按键定义查找
    func keyDefinition(for keyName: String) -> KeyDefinition? {
        rows.flatMap { $0 }.first { $0.keyName == keyName }
    }

    /// 获取所有按键定义的扁平数组
    var allKeys: [KeyDefinition] {
        rows.flatMap { $0 }
    }
}

// MARK: - Builder Helpers

/// 布局构建器辅助扩展
extension KeyDefinition {
    /// 创建普通字符键
    static func key(_ name: String, _ label: String, shift: String? = nil, altGr: String? = nil,
                    type: KeyType = .regular, width: CGFloat? = nil, height: CGFloat? = nil) -> KeyDefinition {
        KeyDefinition(keyName: name, label: label, shiftLabel: shift, altGrLabel: altGr,
                      keyCode: name, keyType: type, widthMultiplier: width, heightMultiplier: height)
    }

    /// 创建修饰键
    static func mod(_ name: String, label: String? = nil, width: CGFloat? = nil, height: CGFloat? = nil) -> KeyDefinition {
        KeyDefinition(keyName: name, label: label ?? name, shiftLabel: nil, altGrLabel: nil,
                      keyCode: name, keyType: .modifier, widthMultiplier: width, heightMultiplier: height)
    }

    /// 创建特殊键
    static func special(_ name: String, label: String? = nil, width: CGFloat? = nil, height: CGFloat? = nil) -> KeyDefinition {
        KeyDefinition(keyName: name, label: label ?? name, shiftLabel: nil, altGrLabel: nil,
                      keyCode: name, keyType: .special, widthMultiplier: width, heightMultiplier: height)
    }

    /// 创建日语特殊键
    static func jpSpecial(_ name: String, label: String, width: CGFloat? = nil) -> KeyDefinition {
        KeyDefinition(keyName: name, label: label, shiftLabel: nil, altGrLabel: nil,
                      keyCode: name, keyType: .japaneseSpecial, widthMultiplier: width)
    }
}

// MARK: - Layout Row Types

/// 布局行类型枚举，用于应用区域变体
enum LayoutRowType: String, CaseIterable {
    case functionRow  // F1-F12 行
    case numberRow    // 数字行
    case row3         // QWERTY/AZERTY 第一行
    case row4         // ASDF 第二行
    case row5         // ZXCV 第三行
    case bottomRow    // 底部修饰键行
}

// MARK: - Preview Helper

#if DEBUG
extension KeyboardLayoutDefinition {
    /// 生成预览用的简化布局描述
    var previewDescription: String {
        let rowStrings = rows.map { row in
            row.map { $0.label }.joined(separator: " ")
        }
        return "\(metadata.name)\n\(rowStrings.joined(separator: "\n"))"
    }
}
#endif