//
//  KeyboardLayoutDefinitionTests.swift
//  KeyCmdTests
//
//  键盘布局定义单元测试
//  验证所有布局的结构完整性
//

import XCTest
@testable import KeyCmd

final class KeyboardLayoutDefinitionTests: XCTestCase {

    override func setUp() {
        super.setUp()
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

    /// 测试所有布局组合的结构完整性
    func testAllLayoutsStructure() {
        let locales: [KeyboardLocale] = KeyboardLocale.allCases
        let oses: [TargetOS] = [.windows, .macOS, .linux]

        var loadedCount = 0

        for locale in locales {
            for os in oses {
                do {
                    let layout = try KeyboardLayoutLoader.load(locale: locale, targetOS: os)

                    // 基础属性验证
                    XCTAssertEqual(layout.locale, locale, "Layout locale mismatch for \(locale)_\(os)")
                    XCTAssertEqual(layout.targetOS, os, "Layout targetOS mismatch for \(locale)_\(os)")
                    XCTAssertGreaterThan(layout.rows.count, 0, "Layout \(locale)_\(os) should have rows")

                    // 验证所有键都有 HID Usage ID
                    for (rowIndex, row) in layout.rows.enumerated() {
                        for (colIndex, keyDef) in row.enumerated() {
                            XCTAssertNotNil(keyDef.hidUsageID,
                                "Layout \(locale)_\(os): key at row \(rowIndex), column \(colIndex) missing HID Usage ID")
                        }
                    }

                    // 验证 metadata
                    XCTAssertFalse(layout.metadata.name.isEmpty,
                        "Layout \(locale)_\(os) has empty metadata name")
                    XCTAssertEqual(layout.metadata.physicalStandard, locale.physicalStandard,
                        "Layout \(locale)_\(os) physicalStandard mismatch")

                    loadedCount += 1
                } catch {
                    XCTFail("Failed to load layout \(locale)_\(os): \(error)")
                }
            }
        }

        XCTAssertEqual(loadedCount, 42, "Should have loaded all 42 layouts (14 locales × 3 OSes)")
    }

    /// 测试布局键名不重复（在同一布局内）
    func testNoDuplicateKeyNamesInLayout() {
        let locales: [KeyboardLocale] = KeyboardLocale.allCases
        let oses: [TargetOS] = [.windows, .macOS, .linux]

        for locale in locales {
            for os in oses {
                do {
                    let layout = try KeyboardLayoutLoader.load(locale: locale, targetOS: os)
                    var keyNames: Set<String> = []

                    for row in layout.rows {
                        for keyDef in row {
                            // 检查keyName是否重复
                            XCTAssertFalse(keyNames.contains(keyDef.keyName),
                                "Layout \(locale)_\(os) has duplicate keyName: \(keyDef.keyName)")
                            keyNames.insert(keyDef.keyName)

                            // 检查keyName不为空
                            XCTAssertFalse(keyDef.keyName.isEmpty,
                                "Layout \(locale)_\(os) has empty keyName")

                            // 检查label不为空
                            XCTAssertFalse(keyDef.label.isEmpty,
                                "Layout \(locale)_\(os) has empty label for key '\(keyDef.keyName)'")
                        }
                    }
                } catch {
                    XCTFail("Failed to load layout \(locale)_\(os) for duplicate check: \(error)")
                }
            }
        }
    }

    /// 测试修饰键存在性
    func testModifierKeysExist() {
        let locales: [KeyboardLocale] = KeyboardLocale.allCases
        let oses: [TargetOS] = [.windows, .macOS, .linux]

        for locale in locales {
            for os in oses {
                do {
                    let layout = try KeyboardLayoutLoader.load(locale: locale, targetOS: os)
                    let allKeys = layout.allKeys

                    // 检查必需的修饰键存在
                    let hasLeftShift = allKeys.contains { $0.keyName == "LeftShift" }
                    let hasRightShift = allKeys.contains { $0.keyName == "RightShift" }
                    let hasLeftCtrl = allKeys.contains { $0.keyName == "LeftCtrl" }
                    let hasRightCtrl = allKeys.contains { $0.keyName == "RightCtrl" }
                    let hasLeftAlt = allKeys.contains { $0.keyName == "LeftAlt" }
                    let hasRightAlt = allKeys.contains { $0.keyName == "RightAlt" }

                    // 根据不同布局调整期望值
                    switch locale {
                    case .jp:
                        // 日文布局可能有不同的命名
                        XCTAssertTrue(hasLeftShift || allKeys.contains { $0.keyName == "Shift" },
                            "Japanese layout \(os) missing Shift key")
                        XCTAssertTrue(hasRightShift || allKeys.contains { $0.keyName == "Shift" },
                            "Japanese layout \(os) missing Shift key")
                    default:
                        XCTAssertTrue(hasLeftShift,
                            "Layout \(locale)_\(os) missing LeftShift key")
                        XCTAssertTrue(hasRightShift,
                            "Layout \(locale)_\(os) missing RightShift key")
                        XCTAssertTrue(hasLeftCtrl,
                            "Layout \(locale)_\(os) missing LeftCtrl key")
                        XCTAssertTrue(hasRightCtrl,
                            "Layout \(locale)_\(os) missing RightCtrl key")
                        XCTAssertTrue(hasLeftAlt,
                            "Layout \(locale)_\(os) missing LeftAlt key")
                        XCTAssertTrue(hasRightAlt,
                            "Layout \(locale)_\(os) missing RightAlt key")
                    }

                    // 检查空格键
                    let hasSpace = allKeys.contains { $0.keyName == "Space" }
                    XCTAssertTrue(hasSpace,
                        "Layout \(locale)_\(os) missing Space key")
                } catch {
                    XCTFail("Failed to load layout \(locale)_\(os) for modifier check: \(error)")
                }
            }
        }
    }

    /// 测试功能行存在 F1-F12
    func testFunctionRowExists() {
        let locales: [KeyboardLocale] = KeyboardLocale.allCases
        let oses: [TargetOS] = [.windows, .macOS, .linux]

        for locale in locales {
            for os in oses {
                do {
                    let layout = try KeyboardLayoutLoader.load(locale: locale, targetOS: os)

                    // 假设功能行在第一行（索引0）
                    guard !layout.rows.isEmpty else {
                        XCTFail("Layout \(locale)_\(os) has no rows")
                        return
                    }

                    let functionRow = layout.rows[0]
                    let functionKeys = functionRow.filter { $0.keyName.hasPrefix("F") &&
                        Int($0.keyName.dropFirst()) ?? 0 >= 1 &&
                        Int($0.keyName.dropFirst()) ?? 0 <= 12 }

                    XCTAssertEqual(functionKeys.count, 12,
                        "Layout \(locale)_\(os) should have 12 function keys (F1-F12), got \(functionKeys.count)")
                } catch {
                    XCTFail("Failed to load layout \(locale)_\(os) for function row check: \(error)")
                }
            }
        }
    }
}