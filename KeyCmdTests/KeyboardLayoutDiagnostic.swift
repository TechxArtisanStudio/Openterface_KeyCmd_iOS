//
//  KeyboardLayoutDiagnostic.swift
//  KeyCmdTests
//
//  诊断键盘布局的实际按键内容，找出映射错误
//

import XCTest
@testable import KeyCmd

class KeyboardLayoutDiagnostic: XCTestCase {

    /// 打印所有布局的按键内容，便于人工检查
    func testPrintAllLayouts() {
        print("\n========== 键盘布局诊断 ==========\n")

        for locale in KeyboardLocale.allCases {
            let layout = KeyboardLayoutManager.shared.layout(for: .windows, locale: locale)
            print("\n>>> \(locale.rawValue) (\(layout.metadata.name)) <<<")
            print("物理标准: \(layout.metadata.physicalStandard.rawValue)")
            print("支持 AltGr: \(layout.metadata.hasAltGr)")
            print("行数: \(layout.rows.count)")
            print("---")

            for (rowIdx, row) in layout.rows.enumerated() {
                let rowLabel: String
                switch rowIdx {
                case 0: rowLabel = "功能行"
                case 1: rowLabel = "数字行"
                case 2: rowLabel = "字母行1(QWERTY)"
                case 3: rowLabel = "字母行2(ASDF)"
                case 4: rowLabel = "字母行3(ZXCV)"
                case 5: rowLabel = "修饰键行"
                default: rowLabel = "行\(rowIdx)"
                }
                let keys = row.map { key -> String in
                    var s = "\(key.keyName)"
                    if key.shiftLabel != nil { s += "(↑:\(key.shiftLabel!))" }
                    if key.altGrLabel != nil { s += "(AltGr:\(key.altGrLabel!))" }
                    s += "[\(key.keyCode)]"
                    return s
                }
                print("\(rowLabel): \(keys.joined(separator: " "))")
            }
        }

        print("\n========== 诊断结束 ==========\n")
    }

    /// 检查重复的 keyName（可能导致 hidKeyName 查找错误）
    func testCheckDuplicateKeyNames() {
        print("\n========== 重复 keyName 检查 ==========\n")

        var foundIssues = false

        for locale in KeyboardLocale.allCases {
            let layout = KeyboardLayoutManager.shared.layout(for: .windows, locale: locale)
            let allKeys = layout.allKeys

            // 统计每个 keyName 出现的次数
            var nameCount: [String: Int] = [:]
            for key in allKeys {
                nameCount[key.keyName, default: 0] += 1
            }

            // 找出重复的（修饰键 Shift/Ctrl/Alt/Win 重复是正常的）
            let allowedDuplicates: Set<String> = ["Shift", "Ctrl", "Alt", "Win", "AltGr"]
            let duplicates = nameCount.filter { $0.value > 1 && !allowedDuplicates.contains($0.key) }

            if !duplicates.isEmpty {
                foundIssues = true
                print("❌ \(locale.rawValue): 发现重复 keyName:")
                for (name, count) in duplicates {
                    print("   - '\(name)' 出现 \(count) 次")
                    // 打印这些重复键的详细信息
                    let dupKeys = allKeys.filter { $0.keyName == name }
                    for k in dupKeys {
                        print("     label='\(k.label)', keyCode='\(k.keyCode)', type=\(k.keyType)")
                    }
                }
            }
        }

        if !foundIssues {
            print("✅ 未发现非法的重复 keyName")
        }
        print("\n========== 检查结束 ==========\n")
    }

    /// 验证德语布局的 QWERTZ 顺序
    func testGermanQWERTZ() {
        print("\n========== 德语 QWERTZ 验证 ==========\n")

        let layout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .de)

        // 字母行1应该是 QWERTZ
        if layout.rows.count > 2 {
            let topRow = layout.rows[2]
            print("字母行1按键顺序:")
            for (i, key) in topRow.enumerated() {
                print("  [\(i)] keyName='\(key.keyName)', label='\(key.label)'")
            }

            // 验证 QWERTZ: 第6个字母应该是 Z 而不是 Y
            // Q W E R T Z U I O P
            let letters = topRow.filter { $0.keyType == .regular || $0.keyName.count == 1 }
            print("\n字母按键: \(letters.map { $0.label }.joined(separator: " "))")

            // 在 QWERTY 中 Y 在位置6，在 QWERTZ 中 Z 在位置6
            if topRow.count > 6 {
                let pos6 = topRow[6]
                print("\n位置6: keyName='\(pos6.keyName)', label='\(pos6.label)'")
                if pos6.keyName.lowercased() == "y" || pos6.label.lowercased() == "y" {
                    print("❌ 德语布局位置6是 Y，应该是 Z！(QWERTZ)")
                } else if pos6.keyName.lowercased() == "z" || pos6.label.lowercased() == "z" {
                    print("✅ 德语布局位置6是 Z (QWERTZ 正确)")
                }
            }
        }

        // 检查字母行3 (ZXCV) - 应该是 YXCV
        if layout.rows.count > 4 {
            let bottomRow = layout.rows[4]
            print("\n字母行3按键:")
            let letters = bottomRow.filter { $0.keyType == .regular || $0.keyName.count == 1 }
            print("字母按键: \(letters.map { $0.label }.joined(separator: " "))")

            // 在 QWERTZ 中，底行第一个字母应该是 Y 而不是 Z
            if let firstLetter = letters.first {
                print("\n底行第一个字母: '\(firstLetter.label)'")
                if firstLetter.keyName.lowercased() == "z" || firstLetter.label.lowercased() == "z" {
                    print("❌ 德语布局底行第一个字母是 Z，应该是 Y！(QWERTZ)")
                } else if firstLetter.keyName.lowercased() == "y" || firstLetter.label.lowercased() == "y" {
                    print("✅ 德语布局底行第一个字母是 Y (QWERTZ 正确)")
                }
            }
        }
        print("\n========== 验证结束 ==========\n")
    }

    /// 验证法语 AZERTY 顺序
    func testFrenchAZERTY() {
        print("\n========== 法语 AZERTY 验证 ==========\n")

        let layout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .fr)

        if layout.rows.count > 2 {
            let topRow = layout.rows[2]
            print("字母行1按键:")
            for (i, key) in topRow.enumerated() {
                print("  [\(i)] keyName='\(key.keyName)', label='\(key.label)'")
            }

            // AZERTY: A Z E R T Y U I O P
            let letters = topRow.filter { $0.keyType == .regular || $0.keyName.count == 1 }
            print("\n字母按键: \(letters.map { $0.label }.joined(separator: " "))")

            if letters.count > 0 {
                let first = letters[0]
                print("\n第一个字母: '\(first.label)'")
                if first.label.lowercased() == "a" {
                    print("✅ 法语布局第一个字母是 A (AZERTY 正确)")
                } else {
                    print("❌ 法语布局第一个字母是 '\(first.label)'，应该是 A (AZERTY)")
                }
            }
        }
        print("\n========== 验证结束 ==========\n")
    }

    /// 验证日语布局特殊按键
    func testJapaneseLayout() {
        print("\n========== 日语布局验证 ==========\n")

        let layout = KeyboardLayoutManager.shared.layout(for: .windows, locale: .jp)
        let allKeys = layout.allKeys

        // 检查特殊按键的 keyCode
        let specialKeys = allKeys.filter { $0.keyType == .japaneseSpecial || $0.keyType == .special }
        print("特殊按键:")
        for key in specialKeys {
            print("  keyName='\(key.keyName)', label='\(key.label)', keyCode='\(key.keyCode)'")
        }

        // 检查 @ 和 [ 的映射
        print("\n@ 和 [ 按键:")
        for key in allKeys where key.keyName == "@" || key.keyName == "[" {
            print("  keyName='\(key.keyName)', label='\(key.label)', keyCode='\(key.keyCode)', shift='\(key.shiftLabel ?? "nil")'")
        }
        print("\n========== 验证结束 ==========\n")
    }

    /// 测试 hidKeyName 解析（这是运行时实际使用的）
    func testHidKeyNameResolution() {
        print("\n========== hidKeyName 解析测试 ==========\n")

        // 测试几个关键地区
        let testCases: [(KeyboardLocale, String, String)] = [
            // (locale, keyName, expectedHidCode)
            (.us, "a", "a"),
            (.us, "1", "1"),
            (.de, "z", "z"),  // 德语中 Z 键
            (.de, "y", "y"),  // 德语中 Y 键
            (.fr, "a", "a"),  // 法语中 A 键
            (.fr, "&", "1"),  // 法语 & 对应数字1的位置
            (.jp, "¥", "IntlBackslash"),
        ]

        for (locale, keyName, expected) in testCases {
            let layout = KeyboardLayoutManager.shared.layout(for: .windows, locale: locale)
            let resolved = layout.keyDefinition(for: keyName)?.keyCode ?? "NOT FOUND"
            let status = resolved == expected ? "✅" : "❌"
            print("\(status) \(locale.rawValue): keyName='\(keyName)' → keyCode='\(resolved)' (期望: '\(expected)')")
        }
        print("\n========== 测试结束 ==========\n")
    }
}
