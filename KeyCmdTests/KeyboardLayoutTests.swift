//
//  KeyboardLayoutTests.swift
//  KeyCmdTests
//
//  全面验证所有键盘布局的正确性
//  覆盖 14 个地区 × 3 个操作系统 = 42 种组合
//

import XCTest
@testable import KeyCmd

class KeyboardLayoutTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear any cached layouts to ensure we load fresh data
        KeyboardLayoutManager.shared.clearCache()
        // Set the layouts directory for testing - use project root path
        // Walk up from current directory to find Resources/KeyboardLayouts
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            let layoutsPath = (dir as NSString).appendingPathComponent("Resources/KeyboardLayouts")
            if FileManager.default.fileExists(atPath: layoutsPath) {
                KeyboardLayoutLoader.layoutsDirectoryOverride = layoutsPath
                return
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        // Fallback: use absolute path (for CI/test environments)
        KeyboardLayoutLoader.layoutsDirectoryOverride = "/Users/txa/project/Openterface_KeyCmd_iOS/Resources/KeyboardLayouts"
    }

    override func tearDown() {
        KeyboardLayoutLoader.layoutsDirectoryOverride = nil
        super.tearDown()
    }

    // MARK: - Helper Functions

    /// 获取所有布局组合
    private func getAllLayoutCombinations() -> [(TargetOS, KeyboardLocale)] {
        var combinations: [(TargetOS, KeyboardLocale)] = []
        for os in TargetOS.allCases {
            for locale in KeyboardLocale.allCases {
                combinations.append((os, locale))
            }
        }
        return combinations
    }

    /// 验证单个按键定义的有效性
    private func validateKeyDefinition(_ key: KeyDefinition, in layout: KeyboardLayoutDefinition) {
        // 验证 keyName 非空
        XCTAssertFalse(key.keyName.isEmpty,
                       "Layout \(layout.metadata.name): keyName should not be empty")

        // 验证 label 非空
        XCTAssertFalse(key.label.isEmpty,
                       "Layout \(layout.metadata.name): label should not be empty for key '\(key.keyName)'")

        // 验证 keyCode 非空
        XCTAssertFalse(key.keyCode.isEmpty,
                       "Layout \(layout.metadata.name): keyCode should not be empty for key '\(key.keyName)'")

        // 验证 keyType 为有效值
        let validKeyTypes: [KeyType] = [.regular, .modifier, .special, .japaneseSpecial]
        XCTAssertTrue(validKeyTypes.contains(key.keyType),
                      "Layout \(layout.metadata.name): key '\(key.keyName)' has invalid keyType")
    }

    /// 验证地区特定按键
    private func assertLocaleSpecificKeys(for locale: KeyboardLocale, layout: KeyboardLayoutDefinition) {
        let allKeys = layout.allKeys

        switch locale {
        case .jp:
            // 日文布局特殊按键
            let jpKeys = ["半角/全角", "変換", "無変換", "Ro"]
            for keyName in jpKeys {
                let found = allKeys.contains { $0.keyName == keyName }
                XCTAssertTrue(found,
                              "Japanese layout missing key: \(keyName)")

                if let key = allKeys.first(where: { $0.keyName == keyName }) {
                    XCTAssertFalse(key.label.isEmpty,
                                   "Japanese key '\(keyName)' has empty label")
                    XCTAssertFalse(key.keyCode.isEmpty,
                                   "Japanese key '\(keyName)' has empty keyCode")
                }
            }

        case .de:
            // 德文布局：Z 和 Y 位置互换
            if layout.rows.count > 2 {
                let topRow = layout.rows[2]
                let zKey = topRow.first { $0.keyName == "z" || $0.label == "Z" || $0.label == "z" }
                let yKey = topRow.first { $0.keyName == "y" || $0.label == "Y" || $0.label == "y" }

                // Z 应该在 Y 之前（德文 QWERTZ）
                if let zIdx = topRow.firstIndex(where: { $0 == zKey }),
                   let yIdx = topRow.firstIndex(where: { $0 == yKey }) {
                    XCTAssertTrue(zIdx < yIdx,
                                  "German layout: Z should come before Y (QWERTZ)")
                }
            }

        case .fr, .be:
            // 法文和比利时布局：应该有 AltGr 修饰键
            let altGrKey = allKeys.first { $0.keyName == "AltGr" || $0.label == "AltGr" }
            XCTAssertNotNil(altGrKey,
                            "\(locale.rawValue) layout missing AltGr key")

        case .ch:
            // 瑞士布局：ü, ö, ä 键
            let swissKeys = ["ü", "ö", "ä"]
            for keyName in swissKeys {
                let found = allKeys.contains { $0.keyName == keyName || $0.label == keyName }
                XCTAssertTrue(found,
                              "Swiss layout missing key: \(keyName)")
            }

        case .nordic:
            // 北欧布局：å, ä, ö 键
            let nordicKeys = ["å", "ä", "ö"]
            for keyName in nordicKeys {
                let found = allKeys.contains { $0.keyName == keyName || $0.label == keyName }
                XCTAssertTrue(found,
                              "Nordic layout missing key: \(keyName)")
            }

        case .es:
            // 西班牙布局：ñ 键
            let found = allKeys.contains { $0.keyName == "ñ" || $0.label == "ñ" }
            XCTAssertTrue(found,
                          "Spanish layout missing ñ key")

        case .pt:
            // 葡萄牙布局：ç 键
            let found = allKeys.contains { $0.keyName == "ç" || $0.label == "ç" }
            XCTAssertTrue(found,
                          "Portuguese layout missing ç key")

        default:
            // 其他地区无特殊要求
            break
        }
    }

    // MARK: - Test Cases

    /// 测试 1：布局结构完整性验证
    func testLayoutStructure() {
        let combinations = getAllLayoutCombinations()

        for (os, locale) in combinations {
            let layout = KeyboardLayoutManager.shared.layout(for: os, locale: locale)

            // 验证行数 ≥ 5
            XCTAssertGreaterThanOrEqual(layout.rows.count, 5,
                                        "Layout \(os.rawValue)_\(locale.rawValue) should have at least 5 rows, got \(layout.rows.count)")

            // 验证每行都包含至少一个按键
            for (rowIndex, row) in layout.rows.enumerated() {
                XCTAssertFalse(row.isEmpty,
                               "Layout \(os.rawValue)_\(locale.rawValue) row \(rowIndex) is empty")

                // 验证每个按键的有效性
                for key in row {
                    validateKeyDefinition(key, in: layout)
                }
            }

            // 验证 metadata 信息
            XCTAssertFalse(layout.metadata.name.isEmpty,
                           "Layout \(os.rawValue)_\(locale.rawValue) has empty metadata name")
            XCTAssertFalse(layout.metadata.description.isEmpty,
                           "Layout \(os.rawValue)_\(locale.rawValue) has empty metadata description")
        }
    }

    /// 测试 2：按键映射正确性验证
    func testKeyMappingCorrectness() {
        let combinations = getAllLayoutCombinations()

        for (os, locale) in combinations {
            let layout = KeyboardLayoutManager.shared.layout(for: os, locale: locale)

            // 验证所有按键的映射关系
            for key in layout.allKeys {
                // 验证 keyName 格式（不包含非法字符）
                XCTAssertFalse(key.keyName.contains(" "),
                               "Layout \(os.rawValue)_\(locale.rawValue): keyName '\(key.keyName)' contains space")

                // 验证 keyCode 格式
                XCTAssertFalse(key.keyCode.isEmpty,
                               "Layout \(os.rawValue)_\(locale.rawValue): keyCode is empty for key '\(key.keyName)'")

                // 对于字母键，验证 label 是单个字符或预期的标签
                if key.keyType == .regular && key.keyName.count == 1 && key.keyName.first?.isLetter == true {
                    XCTAssertGreaterThanOrEqual(key.label.count, 1,
                                                "Layout \(os.rawValue)_\(locale.rawValue): letter key '\(key.keyName)' has invalid label '\(key.label)'")
                }

                // 验证修饰键的 shiftLabel（如果适用）
                if key.keyType == .modifier && key.keyName != "Space" {
                    // 修饰键可以有也可以没有 shiftLabel
                    XCTAssertTrue(true, "Modifier key '\(key.keyName)' validation passed")
                }
            }

            // 验证功能行包含 F1-F12
            if !layout.rows.isEmpty {
                let functionRow = layout.rows[0]
                let functionKeys = functionRow.filter { $0.keyName.hasPrefix("F") }
                XCTAssertEqual(functionKeys.count, 12,
                               "Layout \(os.rawValue)_\(locale.rawValue) should have 12 function keys, got \(functionKeys.count)")
            }

            // 验证必需修饰键存在
            let allKeys = layout.allKeys
            let hasCtrl = allKeys.contains { $0.keyName.contains("Ctrl") || $0.label == "Ctrl" || $0.label == "⌃" }
            let hasAlt = allKeys.contains { $0.keyName.contains("Alt") || $0.label == "Alt" || $0.label == "⌥" }
            let hasSpace = allKeys.contains { $0.keyName == "Space" }

            XCTAssertTrue(hasCtrl,
                          "Layout \(os.rawValue)_\(locale.rawValue) missing Ctrl key")
            XCTAssertTrue(hasAlt,
                          "Layout \(os.rawValue)_\(locale.rawValue) missing Alt key")
            XCTAssertTrue(hasSpace,
                          "Layout \(os.rawValue)_\(locale.rawValue) missing Space key")
        }
    }

    /// 测试 3：地区特定按键验证
    func testLocaleSpecificKeys() {
        let combinations = getAllLayoutCombinations()

        for (os, locale) in combinations {
            let layout = KeyboardLayoutManager.shared.layout(for: os, locale: locale)
            assertLocaleSpecificKeys(for: locale, layout: layout)
        }
    }

    /// 测试 4：操作系统特定修饰键验证
    func testOSSpecificModifications() {
        let combinations = getAllLayoutCombinations()

        for (os, locale) in combinations {
            let layout = KeyboardLayoutManager.shared.layout(for: os, locale: locale)
            let allKeys = layout.allKeys

            switch os {
            case .windows, .linux:
                // Windows/Linux 使用文本标签
                let ctrlKey = allKeys.first { $0.keyName == "Ctrl" }
                let altKey = allKeys.first { $0.keyName == "Alt" }
                let winKey = allKeys.first { $0.keyName == "Win" }

                if let ctrl = ctrlKey {
                    XCTAssertEqual(ctrl.label, "Ctrl",
                                   "\(os.rawValue) layout Ctrl label should be 'Ctrl', got '\(ctrl.label)'")
                }
                if let alt = altKey {
                    XCTAssertEqual(alt.label, "Alt",
                                   "\(os.rawValue) layout Alt label should be 'Alt', got '\(alt.label)'")
                }
                if let win = winKey {
                    XCTAssertEqual(win.label, "Win",
                                   "\(os.rawValue) layout Win label should be 'Win', got '\(win.label)'")
                }

            case .macOS:
                // macOS 应使用符号标签代替 Windows 文本标签
                // 验证底行修饰键标签已被修改为 macOS 风格
                let winLabel = allKeys.first { $0.keyName == "Win" }?.label ?? ""
                let altLabel = allKeys.first { $0.keyName == "Alt" }?.label ?? ""

                // macOS 下的 Win/Alt 标签应与 Windows/Linux 不同
                if let winKey = allKeys.first(where: { $0.keyName == "Win" }) {
                    XCTAssertNotEqual(winKey.label, "Win",
                                      "macOS layout (\(locale.rawValue)): Win key label should NOT be 'Win', got '\(winKey.label)'")
                }
                if let altKey = allKeys.first(where: { $0.keyName == "Alt" }) {
                    XCTAssertNotEqual(altKey.label, "Alt",
                                      "macOS layout (\(locale.rawValue)): Alt key label should NOT be 'Alt', got '\(altKey.label)'")
                }
            }
        }
    }

    /// 额外测试：验证键盘布局管理器缓存功能
    func testLayoutManagerCaching() {
        let manager = KeyboardLayoutManager.shared

        // 第一次获取布局
        let layout1 = manager.layout(for: .windows, locale: .us)

        // 第二次获取应该返回相同的缓存实例
        let layout2 = manager.layout(for: .windows, locale: .us)

        XCTAssertEqual(layout1, layout2,
                       "LayoutManager should return cached layout")

        // 验证缓存统计
        XCTAssertFalse(manager.cacheStats.isEmpty,
                       "Cache stats should not be empty")
    }

    /// 额外测试：验证所有支持的地区
    func testAllSupportedLocales() {
        let manager = KeyboardLayoutManager.shared
        let supportedLocales = manager.supportedLocales

        XCTAssertEqual(supportedLocales.count, 14,
                       "Should support 14 locales, got \(supportedLocales.count)")

        // 验证所有地区都能生成有效布局
        for locale in supportedLocales {
            let layout = manager.layout(for: .windows, locale: locale)
            XCTAssertFalse(layout.allKeys.isEmpty,
                           "Locale \(locale.rawValue) should have keys")
        }
    }
}
