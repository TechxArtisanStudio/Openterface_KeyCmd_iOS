# 多国键盘布局重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重构键盘布局系统，使用 USB HID Usage ID 作为统一键码标准，实现活动键盘布局检测，完善修饰键和死键处理，解决当前布局检测不准确、键码映射不一致的问题。

**Architecture:** 采用分层架构：(1) 基础设施层 - HIDUsageID 枚举、KeyboardState 状态管理器、KeyboardTranslationTable 翻译表；(2) 布局定义层 - 14个布局的完整字符映射；(3) 检测层 - iOS/macOS 活动键盘检测；(4) 处理层 - 修饰键、死键、AltGr 组合键处理。

**Tech Stack:** Swift 5.9+, iOS 17+, macOS 14+, SwiftUI, USB HID Usage Tables 1.12

**Spec:** `docs/superpowers/specs/2026-10-10-keyboard-layout-refactor-plan.md`

## Global Constraints

- 使用 USB HID Usage ID (Usage Page 0x07) 作为统一键码标准
- 支持 14 个 KeyboardLocale × 3 个 TargetOS = 42 种布局组合
- 布局查找缓存命中 < 1ms，翻译表查找 < 0.1ms
- 单元测试覆盖率 > 90%
- 无 Force Unwrap / 隐式解包风险
- 文档注释覆盖所有 public API
- iOS 17+ / macOS 14+ 兼容性

## Review Focus

1. **HID Usage ID 完整性** - 所有标准键 (0x04-0xE7) 及日文特殊键 (0x87-0x92) 必须完整定义，测试：验证枚举值与 USB HID 规范一致
2. **布局检测准确性** - iOS 使用 UITextInputMode，macOS 使用 TIS API，测试：模拟布局切换验证自动检测
3. **修饰键状态一致性** - Shift/AltGr/Ctrl 状态必须与实际按键状态同步，测试：验证修饰键字节计算正确
4. **死键组合正确性** - 5种死键 (´`^¨~) 与元音字母组合必须产生正确字符，测试：验证所有组合
5. **跨平台一致性** - 同一布局在不同 OS 上的字符映射必须一致，测试：14布局×3OS 结构验证

---

## 阶段 1：基础设施建设

### Task 1.1: 创建 HIDUsageID 枚举

**Files:**
- Create: `KeyCmd/HIDUsageID.swift`
- Test: `KeyCmdTests/HIDUsageIDTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `enum HIDUsageID: UInt8` 包含所有标准键和日文特殊键

- [ ] **Step 1: 创建 HIDUsageID 枚举基础结构**

```swift
// KeyCmd/HIDUsageID.swift
import Foundation

/// USB HID Usage IDs (Usage Page 0x07: Keyboard/Keypad)
/// 参考：USB HID Usage Tables 1.12
enum HIDUsageID: UInt8, CaseIterable, Codable {
    // 字母键 (0x04 - 0x1D)
    case keyboardA = 0x04
    case keyboardB = 0x05
    case keyboardC = 0x06
    case keyboardD = 0x07
    case keyboardE = 0x08
    case keyboardF = 0x09
    case keyboardG = 0x0A
    case keyboardH = 0x0B
    case keyboardI = 0x0C
    case keyboardJ = 0x0D
    case keyboardK = 0x0E
    case keyboardL = 0x0F
    case keyboardM = 0x10
    case keyboardN = 0x11
    case keyboardO = 0x12
    case keyboardP = 0x13
    case keyboardQ = 0x14
    case keyboardR = 0x15
    case keyboardS = 0x16
    case keyboardT = 0x17
    case keyboardU = 0x18
    case keyboardV = 0x19
    case keyboardW = 0x1A
    case keyboardX = 0x1B
    case keyboardY = 0x1C
    case keyboardZ = 0x1D
    
    // 数字键 (0x1E - 0x27)
    case keyboard1 = 0x1E
    case keyboard2 = 0x1F
    case keyboard3 = 0x20
    case keyboard4 = 0x21
    case keyboard5 = 0x22
    case keyboard6 = 0x23
    case keyboard7 = 0x24
    case keyboard8 = 0x25
    case keyboard9 = 0x26
    case keyboard0 = 0x27
    
    // 控制键 (0x28 - 0x2F)
    case keyboardEnter = 0x28
    case keyboardEscape = 0x29
    case keyboardBackspace = 0x2A
    case keyboardTab = 0x2B
    case keyboardSpace = 0x2C
    case keyboardMinus = 0x2D
    case keyboardEqual = 0x2E
    case keyboardLeftBracket = 0x2F
    case keyboardRightBracket = 0x30
    case keyboardBackslash = 0x31
    case keyboardNonUSHash = 0x32
    case keyboardSemicolon = 0x33
    case keyboardQuote = 0x34
    case keyboardGraveAccent = 0x35
    case keyboardComma = 0x36
    case keyboardPeriod = 0x37
    case keyboardSlash = 0x38
    case keyboardCapsLock = 0x39
    
    // 功能键 (0x3A - 0x45)
    case keyboardF1 = 0x3A
    case keyboardF2 = 0x3B
    case keyboardF3 = 0x3C
    case keyboardF4 = 0x3D
    case keyboardF5 = 0x3E
    case keyboardF6 = 0x3F
    case keyboardF7 = 0x40
    case keyboardF8 = 0x41
    case keyboardF9 = 0x42
    case keyboardF10 = 0x43
    case keyboardF11 = 0x44
    case keyboardF12 = 0x45
    
    // 修饰键 (0xE0 - 0xE7)
    case keyboardLeftCtrl = 0xE0
    case keyboardLeftShift = 0xE1
    case keyboardLeftAlt = 0xE2
    case keyboardLeftGUI = 0xE3
    case keyboardRightCtrl = 0xE4
    case keyboardRightShift = 0xE5
    case keyboardRightAlt = 0xE6  // AltGr
    case keyboardRightGUI = 0xE7
    
    // 日语特殊键 (0x87 - 0x92)
    case keyboardInternational1 = 0x87  // Ro
    case keyboardInternational2 = 0x88  // かな
    case keyboardInternational3 = 0x89  // 変換
    case keyboardInternational4 = 0x8A  // 無変換
    case keyboardInternational5 = 0x8B  // katakana/hiragana
}
```

- [ ] **Step 2: 编写 HIDUsageID 单元测试**

```swift
// KeyCmdTests/HIDUsageIDTests.swift
import XCTest
@testable import KeyCmd

final class HIDUsageIDTests: XCTestCase {
    
    func testLetterKeyValues() {
        XCTAssertEqual(HIDUsageID.keyboardA.rawValue, 0x04)
        XCTAssertEqual(HIDUsageID.keyboardZ.rawValue, 0x1D)
    }
    
    func testNumberKeyValues() {
        XCTAssertEqual(HIDUsageID.keyboard1.rawValue, 0x1E)
        XCTAssertEqual(HIDUsageID.keyboard0.rawValue, 0x27)
    }
    
    func testModifierKeyValues() {
        XCTAssertEqual(HIDUsageID.keyboardLeftCtrl.rawValue, 0xE0)
        XCTAssertEqual(HIDUsageID.keyboardRightAlt.rawValue, 0xE6)
    }
    
    func testJapaneseKeyValues() {
        XCTAssertEqual(HIDUsageID.keyboardInternational1.rawValue, 0x87)
        XCTAssertEqual(HIDUsageID.keyboardInternational5.rawValue, 0x8B)
    }
    
    func testAllCasesCount() {
        // 确保所有键都被定义
        XCTAssertGreaterThan(HIDUsageID.allCases.count, 80)
    }
}
```

- [ ] **Step 3: 运行测试验证**

Run: `xcodebuild test -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/HIDUsageIDTests`
Expected: 所有测试通过

- [ ] **Step 4: 提交代码**

```bash
git add KeyCmd/HIDUsageID.swift KeyCmdTests/HIDUsageIDTests.swift
git commit -m "feat: add HIDUsageID enum with USB HID standard key codes"
```

---

### Task 1.2: 扩展 KeyDefinition 增加 hidUsageID

**Files:**
- Modify: `KeyCmd/Managers/KeyboardLayoutDefinition.swift:46-73`
- Test: `KeyCmdTests/KeyDefinitionTests.swift`

**Interfaces:**
- Consumes: `HIDUsageID` from Task 1.1
- Produces: `KeyDefinition` 结构体包含 `hidUsageID: HIDUsageID` 字段

- [ ] **Step 1: 修改 KeyDefinition 结构体**

在 `KeyboardLayoutDefinition.swift` 中修改 `KeyDefinition`：

```swift
struct KeyDefinition: Codable, Equatable, Hashable {
    let keyName: String
    let label: String
    let shiftLabel: String?
    let altGrLabel: String?
    let keyCode: String
    let hidUsageID: HIDUsageID  // 新增字段
    let keyType: KeyType
    let widthMultiplier: CGFloat?
    let heightMultiplier: CGFloat?
    
    init(keyName: String,
         label: String,
         shiftLabel: String? = nil,
         altGrLabel: String? = nil,
         keyCode: String? = nil,
         hidUsageID: HIDUsageID,  // 新增参数
         keyType: KeyType = .regular,
         widthMultiplier: CGFloat? = nil,
         heightMultiplier: CGFloat? = nil) {
        self.keyName = keyName
        self.label = label
        self.shiftLabel = shiftLabel
        self.altGrLabel = altGrLabel
        self.keyCode = keyCode ?? keyName
        self.hidUsageID = hidUsageID
        self.keyType = keyType
        self.widthMultiplier = widthMultiplier
        self.heightMultiplier = heightMultiplier
    }
    
    /// 获取HID Usage ID的原始值
    var hidUsageValue: UInt8 {
        hidUsageID.rawValue
    }
}
```

- [ ] **Step 2: 添加辅助构造函数**

```swift
extension KeyDefinition {
    static func key(_ name: String, _ label: String, shift: String? = nil, altGr: String? = nil,
                    hid: HIDUsageID, type: KeyType = .regular, width: CGFloat? = nil, height: CGFloat? = nil) -> KeyDefinition {
        KeyDefinition(keyName: name, label: label, shiftLabel: shift, altGrLabel: altGr,
                      hidUsageID: hid, keyType: type, widthMultiplier: width, heightMultiplier: height)
    }
    
    static func mod(_ name: String, label: String? = nil, hid: HIDUsageID, width: CGFloat? = nil, height: CGFloat? = nil) -> KeyDefinition {
        KeyDefinition(keyName: name, label: label ?? name, shiftLabel: nil, altGrLabel: nil,
                      hidUsageID: hid, keyType: .modifier, widthMultiplier: width, heightMultiplier: height)
    }
}
```

- [ ] **Step 3: 编写 KeyDefinition 测试**

```swift
// KeyCmdTests/KeyDefinitionTests.swift
import XCTest
@testable import KeyCmd

final class KeyDefinitionTests: XCTestCase {
    
    func testKeyDefinitionWithHID() {
        let keyDef = KeyDefinition.key("q", "Q", hid: .keyboardQ)
        XCTAssertEqual(keyDef.hidUsageID, .keyboardQ)
        XCTAssertEqual(keyDef.hidUsageValue, 0x14)
    }
    
    func testModifierKeyDefinition() {
        let shiftKey = KeyDefinition.mod("Shift", hid: .keyboardLeftShift, width: 1.5)
        XCTAssertEqual(shiftKey.keyType, .modifier)
        XCTAssertEqual(shiftKey.hidUsageID, .keyboardLeftShift)
    }
    
    func testKeyWithAltGr() {
        let keyDef = KeyDefinition.key("e", "E", shift: "€", altGr: "é", hid: .keyboardE)
        XCTAssertEqual(keyDef.altGrLabel, "é")
    }
}
```

- [ ] **Step 4: 运行测试验证**

Run: `xcodebuild test -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/KeyDefinitionTests`
Expected: 所有测试通过

- [ ] **Step 5: 提交代码**

```bash
git add KeyCmd/Managers/KeyboardLayoutDefinition.swift KeyCmdTests/KeyDefinitionTests.swift
git commit -m "feat: add hidUsageID field to KeyDefinition"
```

---

### Task 1.3: 创建 KeyboardState 状态管理器

**Files:**
- Create: `KeyCmd/KeyboardState.swift`
- Test: `KeyCmdTests/KeyboardStateTests.swift`

**Interfaces:**
- Consumes: `HIDUsageID` from Task 1.1
- Produces: `KeyboardState` 类管理修饰键和死键状态

- [ ] **Step 1: 创建 DeadKey 枚举**

```swift
// KeyCmd/KeyboardState.swift
import Foundation

/// 死键类型
enum DeadKey: String, Codable {
    case acute       // ´
    case grave       // `
    case circumflex  // ^
    case diaeresis   // ¨
    case tilde       // ~
    
    /// 将死键与基础字符组合
    func combine(with baseChar: Character) -> Character? {
        let baseStr = String(baseChar)
        
        switch self {
        case .acute:
            let map: [Character: Character] = ["a": "á", "e": "é", "i": "í", "o": "ó", "u": "ú", "y": "ý"]
            return map[baseChar]
        case .grave:
            let map: [Character: Character] = ["a": "à", "e": "è", "i": "ì", "o": "ò", "u": "ù"]
            return map[baseChar]
        case .circumflex:
            let map: [Character: Character] = ["a": "â", "e": "ê", "i": "î", "o": "ô", "u": "û"]
            return map[baseChar]
        case .diaeresis:
            let map: [Character: Character] = ["a": "ä", "e": "ë", "i": "ï", "o": "ö", "u": "ü", "y": "ÿ"]
            return map[baseChar]
        case .tilde:
            let map: [Character: Character] = ["a": "ã", "n": "ñ", "o": "õ"]
            return map[baseChar]
        }
    }
}
```

- [ ] **Step 2: 创建 KeyboardState 类**

```swift
/// 键盘状态管理器
class KeyboardState {
    static let shared = KeyboardState()
    
    // 修饰键状态
    private(set) var isShiftPressed = false
    private(set) var isAltGrPressed = false
    private(set) var isCtrlPressed = false
    private(set) var isAltPressed = false
    
    // 死键状态
    private(set) var pendingDeadKey: DeadKey?
    
    private init() {}
    
    func updateModifierState(key: HIDUsageID, pressed: Bool) {
        switch key {
        case .keyboardLeftShift, .keyboardRightShift:
            isShiftPressed = pressed
        case .keyboardRightAlt:  // AltGr
            isAltGrPressed = pressed
        case .keyboardLeftCtrl, .keyboardRightCtrl:
            isCtrlPressed = pressed
        case .keyboardLeftAlt:
            isAltPressed = pressed
        default:
            break
        }
    }
    
    func setDeadKey(_ deadKey: DeadKey?) {
        pendingDeadKey = deadKey
    }
    
    /// 获取当前修饰键字节（用于HID报告）
    var modifierByte: UInt8 {
        var byte: UInt8 = 0
        if isCtrlPressed { byte |= 0x01 }
        if isShiftPressed { byte |= 0x02 }
        if isAltPressed { byte |= 0x04 }
        if isAltGrPressed { byte |= 0x40 }  // Right Alt
        return byte
    }
    
    /// 重置所有状态
    func reset() {
        isShiftPressed = false
        isAltGrPressed = false
        isCtrlPressed = false
        isAltPressed = false
        pendingDeadKey = nil
    }
}
```

- [ ] **Step 3: 编写 KeyboardState 测试**

```swift
// KeyCmdTests/KeyboardStateTests.swift
import XCTest
@testable import KeyCmd

final class KeyboardStateTests: XCTestCase {
    
    var state: KeyboardState!
    
    override func setUp() {
        super.setUp()
        state = KeyboardState.shared
        state.reset()
    }
    
    func testModifierStateUpdate() {
        state.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertTrue(state.isShiftPressed)
        
        state.updateModifierState(key: .keyboardLeftShift, pressed: false)
        XCTAssertFalse(state.isShiftPressed)
    }
    
    func testAltGrState() {
        state.updateModifierState(key: .keyboardRightAlt, pressed: true)
        XCTAssertTrue(state.isAltGrPressed)
    }
    
    func testModifierByte() {
        state.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertEqual(state.modifierByte, 0x02)
        
        state.updateModifierState(key: .keyboardLeftCtrl, pressed: true)
        XCTAssertEqual(state.modifierByte, 0x03)  // 0x01 | 0x02
    }
    
    func testDeadKeyCombination() {
        XCTAssertEqual(DeadKey.circumflex.combine(with: "e"), "ê")
        XCTAssertEqual(DeadKey.acute.combine(with: "e"), "é")
        XCTAssertEqual(DeadKey.diaeresis.combine(with: "u"), "ü")
    }
    
    func testReset() {
        state.updateModifierState(key: .keyboardLeftShift, pressed: true)
        state.setDeadKey(.acute)
        state.reset()
        
        XCTAssertFalse(state.isShiftPressed)
        XCTAssertNil(state.pendingDeadKey)
    }
}
```

- [ ] **Step 4: 运行测试验证**

Run: `xcodebuild test -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/KeyboardStateTests`
Expected: 所有测试通过

- [ ] **Step 5: 提交代码**

```bash
git add KeyCmd/KeyboardState.swift KeyCmdTests/KeyboardStateTests.swift
git commit -m "feat: add KeyboardState manager for modifier and dead key tracking"
```

---

### Task 1.4: 创建 KeyboardTranslationTable 翻译表

**Files:**
- Create: `KeyCmd/KeyboardTranslationTable.swift`
- Test: `KeyCmdTests/KeyboardTranslationTableTests.swift`

**Interfaces:**
- Consumes: `HIDUsageID`, `KeyboardLayoutDefinition`
- Produces: `KeyboardTranslationTable` 提供 O(1) 查找

- [ ] **Step 1: 创建 KeyboardTranslationTable 结构体**

```swift
// KeyCmd/KeyboardTranslationTable.swift
import Foundation

/// 键盘翻译表
/// 用于在不同表示之间转换
struct KeyboardTranslationTable {
    /// HID Usage ID -> 物理位置
    private let hidToPosition: [HIDUsageID: (row: Int, column: Int)]
    
    /// 物理位置 -> HID Usage ID
    private let positionToHid: [String: HIDUsageID]
    
    /// 字符 -> HID Usage ID（考虑布局）
    private let charToHid: [Character: HIDUsageID]
    
    init(layout: KeyboardLayoutDefinition) {
        var hidToPos: [HIDUsageID: (Int, Int)] = [:]
        var posToHid: [String: HIDUsageID] = [:]
        var charToH: [Character: HIDUsageID] = [:]
        
        for (rowIndex, row) in layout.rows.enumerated() {
            for (colIndex, keyDef) in row.enumerated() {
                // HID -> 位置
                hidToPos[keyDef.hidUsageID] = (rowIndex, colIndex)
                
                // 位置 -> HID
                let posKey = "\(rowIndex)_\(colIndex)"
                posToHid[posKey] = keyDef.hidUsageID
                
                // 字符 -> HID
                if let firstChar = keyDef.label.first {
                    charToH[firstChar] = keyDef.hidUsageID
                }
                if let shiftLabel = keyDef.shiftLabel, let firstChar = shiftLabel.first {
                    charToH[firstChar] = keyDef.hidUsageID
                }
                if let altGrLabel = keyDef.altGrLabel, let firstChar = altGrLabel.first {
                    charToH[firstChar] = keyDef.hidUsageID
                }
            }
        }
        
        self.hidToPosition = hidToPos
        self.positionToHid = posToHid
        self.charToHid = charToH
    }
    
    func hidUsageID(forPosition row: Int, column: Int) -> HIDUsageID? {
        return positionToHid["\(row)_\(column)"]
    }
    
    func hidUsageID(forCharacter char: Character) -> HIDUsageID? {
        return charToHid[char]
    }
    
    func position(forHID hid: HIDUsageID) -> (row: Int, column: Int)? {
        return hidToPosition[hid]
    }
}
```

- [ ] **Step 2: 编写翻译表测试**

```swift
// KeyCmdTests/KeyboardTranslationTableTests.swift
import XCTest
@testable import KeyCmd

final class KeyboardTranslationTableTests: XCTestCase {
    
    func testHIDToPosition() {
        let layout = KeyboardLayoutBuilders.buildLayout(for: .us, targetOS: .windows)
        let table = KeyboardTranslationTable(layout: layout)
        
        if let pos = table.position(forHID: .keyboardQ) {
            XCTAssertEqual(pos.row, 2)  // QWERTY行
            XCTAssertGreaterThanOrEqual(pos.column, 0)
        } else {
            XCTFail("Position not found for keyboardQ")
        }
    }
    
    func testCharacterToHID() {
        let layout = KeyboardLayoutBuilders.buildLayout(for: .us, targetOS: .windows)
        let table = KeyboardTranslationTable(layout: layout)
        
        XCTAssertEqual(table.hidUsageID(forCharacter: "q"), .keyboardQ)
        XCTAssertEqual(table.hidUsageID(forCharacter: "Q"), .keyboardQ)
    }
    
    func testPositionToHID() {
        let layout = KeyboardLayoutBuilders.buildLayout(for: .us, targetOS: .windows)
        let table = KeyboardTranslationTable(layout: layout)
        
        // 测试某个已知位置
        if let hid = table.hidUsageID(forPosition: 2, column: 1) {
            XCTAssertEqual(hid, .keyboardQ)
        }
    }
}
```

- [ ] **Step 3: 运行测试验证**

Run: `xcodebuild test -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/KeyboardTranslationTableTests`
Expected: 所有测试通过

- [ ] **Step 4: 提交代码**

```bash
git add KeyCmd/KeyboardTranslationTable.swift KeyCmdTests/KeyboardTranslationTableTests.swift
git commit -m "feat: add KeyboardTranslationTable for O(1) key lookup"
```

---

### Task 1.5: 基础设施集成测试

**Files:**
- Test: `KeyCmdTests/KeyboardInfrastructureTests.swift`

**Interfaces:**
- Consumes: Task 1.1-1.4 的所有组件

- [ ] **Step 1: 编写集成测试**

```swift
// KeyCmdTests/KeyboardInfrastructureTests.swift
import XCTest
@testable import KeyCmd

final class KeyboardInfrastructureTests: XCTestCase {
    
    func testHIDUsageIDCompleteness() {
        // 验证所有必要的键都已定义
        let requiredKeys: [HIDUsageID] = [
            .keyboardA, .keyboardZ, .keyboard1, .keyboard0,
            .keyboardEnter, .keyboardEscape, .keyboardSpace,
            .keyboardLeftShift, .keyboardRightAlt
        ]
        
        for key in requiredKeys {
            XCTAssertNotNil(HIDUsageID(rawValue: key.rawValue))
        }
    }
    
    func testKeyDefinitionIntegration() {
        let keyDef = KeyDefinition.key("a", "A", shift: "A", hid: .keyboardA)
        XCTAssertEqual(keyDef.hidUsageID, .keyboardA)
        XCTAssertEqual(keyDef.label, "A")
    }
    
    func testKeyboardStateIntegration() {
        let state = KeyboardState.shared
        state.reset()
        
        state.updateModifierState(key: .keyboardLeftShift, pressed: true)
        XCTAssertTrue(state.isShiftPressed)
        XCTAssertEqual(state.modifierByte & 0x02, 0x02)
    }
    
    func testTranslationTableIntegration() {
        let layout = KeyboardLayoutBuilders.buildLayout(for: .us, targetOS: .windows)
        let table = KeyboardTranslationTable(layout: layout)
        
        // 验证查找性能
        let startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<1000 {
            _ = table.hidUsageID(forCharacter: "a")
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(elapsed, 0.1)  // 1000次查找应<0.1秒
    }
}
```

- [ ] **Step 2: 运行所有基础设施测试**

Run: `xcodebuild test -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/KeyboardInfrastructureTests`
Expected: 所有测试通过

- [ ] **Step 3: 提交代码**

```bash
git add KeyCmdTests/KeyboardInfrastructureTests.swift
git commit -m "test: add infrastructure integration tests"
```

---

## 阶段 2：JSON 布局定义系统（参考 VirtualBox）

### Task 2.0: 设计 JSON 布局架构（VirtualBox 风格）

**Files:**
- Create: `docs/superpowers/specs/keyboard-layout-json-schema.md`

**目标:** 设计 JSON schema，参考 VirtualBox 的 devhid.cpp 方法，为每个 HID Usage ID 定义完整的字符映射

- [ ] **Step 1: 设计 JSON Schema**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Keyboard Layout Definition",
  "type": "object",
  "properties": {
    "locale": {
      "type": "string",
      "enum": ["us", "uk", "de", "fr", "es", "it", "pt", "jp", "cn", "ca", "au", "be", "ch", "nordic"]
    },
    "targetOS": {
      "type": "string",
      "enum": ["windows", "macos", "linux"]
    },
    "metadata": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "description": { "type": "string" },
        "physicalStandard": { "type": "string", "enum": ["ansi", "iso", "jis"] },
        "hasAltGr": { "type": "boolean" }
      },
      "required": ["name", "physicalStandard"]
    },
    "keys": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "hidUsageID": { "type": "integer", "minimum": 0, "maximum": 255 },
          "keyName": { "type": "string" },
          "label": { "type": "string" },
          "shiftLabel": { "type": "string" },
          "altGrLabel": { "type": "string" },
          "deadKey": { "type": "string", "enum": ["acute", "grave", "circumflex", "diaeresis", "tilde"] },
          "keyType": { "type": "string", "enum": ["regular", "modifier", "special"], "default": "regular" },
          "width": { "type": "number" },
          "row": { "type": "integer" },
          "column": { "type": "integer" }
        },
        "required": ["hidUsageID", "keyName", "label", "row", "column"]
      }
    }
  },
  "required": ["locale", "targetOS", "metadata", "keys"]
}
```

- [ ] **Step 2: 编写设计文档**

创建 `docs/superpowers/specs/keyboard-layout-json-schema.md` 详细说明：
- JSON schema 的设计原则
- 与 VirtualBox devhid.cpp 的对应关系
- 每个 HID Usage ID 的字符映射规则
- 死键、AltGr 组合的处理方式

- [ ] **Step 3: 提交设计文档**

```bash
git add docs/superpowers/specs/keyboard-layout-json-schema.md
git commit -m "docs: add JSON schema design for keyboard layouts"
```

---

### Task 2.1: 创建 JSON 布局加载器

**Files:**
- Create: `KeyCmd/KeyboardLayoutLoader.swift`
- Create: `Resources/KeyboardLayouts/` 目录
- Test: `KeyCmdTests/KeyboardLayoutLoaderTests.swift`

**Interfaces:**
- Consumes: JSON 布局文件
- Produces: `KeyboardLayoutDefinition` 对象

- [ ] **Step 1: 创建 KeyboardLayoutLoader**

```swift
// KeyCmd/KeyboardLayoutLoader.swift
import Foundation

/// 从 JSON 文件加载键盘布局
struct KeyboardLayoutLoader {
    
    /// 从 JSON 文件加载布局
    static func load(locale: KeyboardLocale, targetOS: TargetOS) throws -> KeyboardLayoutDefinition {
        let filename = "\(locale.rawValue.lowercased())_\(targetOS.rawValue.lowercased()).json"
        
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "KeyboardLayouts") else {
            throw KeyboardLayoutError.fileNotFound(filename)
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let jsonLayout = try decoder.decode(JSONKeyboardLayout.self, from: data)
        
        return convertToLayoutDefinition(jsonLayout)
    }
    
    /// 从 JSON 对象转换为 KeyboardLayoutDefinition
    private static func convertToLayoutDefinition(_ json: JSONKeyboardLayout) -> KeyboardLayoutDefinition {
        // 按行组织按键
        let maxRow = json.keys.map { $0.row }.max() ?? 0
        var rows: [KeyRow] = Array(repeating: [], count: maxRow + 1)
        
        for jsonKey in json.keys {
            let keyDef = convertKeyDefinition(jsonKey)
            rows[jsonKey.row].append(keyDef)
        }
        
        // 按列排序每行的按键
        for i in 0..<rows.count {
            rows[i].sort { key1, key2 in
                // 需要从原始 JSON 数据获取 column 信息
                // 这里简化处理
                return false
            }
        }
        
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
            locale: json.locale,
            targetOS: json.targetOS,
            rows: rows,
            metadata: metadata
        )
    }
    
    private static func convertKeyDefinition(_ jsonKey: JSONKeyDefinition) -> KeyDefinition {
        let hidUsageID = HIDUsageID(rawValue: jsonKey.hidUsageID) ?? .keyboardA
        
        return KeyDefinition(
            keyName: jsonKey.keyName,
            label: jsonKey.label,
            shiftLabel: jsonKey.shiftLabel,
            altGrLabel: jsonKey.altGrLabel,
            hidUsageID: hidUsageID,
            keyType: jsonKey.keyType ?? .regular,
            widthMultiplier: jsonKey.width
        )
    }
}

/// JSON 布局数据结构
struct JSONKeyboardLayout: Codable {
    let locale: KeyboardLocale
    let targetOS: TargetOS
    let metadata: JSONLayoutMetadata
    let keys: [JSONKeyDefinition]
}

struct JSONLayoutMetadata: Codable {
    let name: String
    let description: String?
    let physicalStandard: KeyboardLocale.PhysicalStandard
    let hasAltGr: Bool?
    let rowHeights: [CGFloat]?
    let keySpacing: CGFloat?
    let rowSpacing: CGFloat?
    let padding: LayoutPadding?
    let fixedKeyWidths: [String: CGFloat]?
}

struct JSONKeyDefinition: Codable {
    let hidUsageID: UInt8
    let keyName: String
    let label: String
    let shiftLabel: String?
    let altGrLabel: String?
    let deadKey: String?
    let keyType: KeyType?
    let width: CGFloat?
    let row: Int
    let column: Int
}

enum KeyboardLayoutError: Error {
    case fileNotFound(String)
    case invalidFormat(String)
}
```

- [ ] **Step 2: 创建示例 JSON 布局文件**

创建 `Resources/KeyboardLayouts/us_windows.json`:

```json
{
  "locale": "us",
  "targetOS": "windows",
  "metadata": {
    "name": "US QWERTY",
    "description": "Standard US QWERTY layout (ANSI)",
    "physicalStandard": "ansi",
    "hasAltGr": false,
    "rowHeights": [0.1, 0.1, 0.2, 0.2, 0.2, 0.2],
    "keySpacing": 3,
    "rowSpacing": 6,
    "padding": {"top": 8, "leading": 8, "bottom": 8, "trailing": 8},
    "fixedKeyWidths": {"Space": 200}
  },
  "keys": [
    // 功能行
    {"hidUsageID": 41, "keyName": "Esc", "label": "Esc", "row": 0, "column": 0},
    {"hidUsageID": 58, "keyName": "F1", "label": "F1", "row": 0, "column": 1},
    // ... 更多功能键 ...
    
    // 数字行
    {"hidUsageID": 53, "keyName": "`", "label": "`", "shiftLabel": "~", "row": 1, "column": 0},
    {"hidUsageID": 30, "keyName": "1", "label": "1", "shiftLabel": "!", "row": 1, "column": 1},
    {"hidUsageID": 31, "keyName": "2", "label": "2", "shiftLabel": "@", "row": 1, "column": 2},
    // ... 更多数字键 ...
    
    // QWERTY行
    {"hidUsageID": 20, "keyName": "q", "label": "Q", "row": 2, "column": 1},
    {"hidUsageID": 26, "keyName": "w", "label": "W", "row": 2, "column": 2},
    // ... 更多字母键 ...
  ]
}
```

- [ ] **Step 3: 编写加载器测试**

```swift
// KeyCmdTests/KeyboardLayoutLoaderTests.swift
import XCTest
@testable import KeyCmd

final class KeyboardLayoutLoaderTests: XCTestCase {
    
    func testLoadUSLayout() throws {
        let layout = try KeyboardLayoutLoader.load(locale: .us, targetOS: .windows)
        
        XCTAssertEqual(layout.locale, .us)
        XCTAssertEqual(layout.targetOS, .windows)
        XCTAssertGreaterThan(layout.rows.count, 0)
        
        // 验证所有键都有 HID Usage ID
        for row in layout.rows {
            for keyDef in row {
                XCTAssertNotNil(keyDef.hidUsageID)
            }
        }
    }
    
    func testLoadAllLayouts() throws {
        let locales: [KeyboardLocale] = KeyboardLocale.allCases
        let oses: [TargetOS] = [.windows, .macos, .linux]
        
        for locale in locales {
            for os in oses {
                do {
                    let layout = try KeyboardLayoutLoader.load(locale: locale, targetOS: os)
                    XCTAssertEqual(layout.locale, locale)
                    XCTAssertEqual(layout.targetOS, os)
                } catch {
                    XCTFail("Failed to load \(locale) \(os): \(error)")
                }
            }
        }
    }
}
```

- [ ] **Step 4: 运行测试验证并提交**

---

### Task 2.2: 创建完整的 JSON 布局文件（14 locales × 3 OSes）

**Files:**
- Create: `Resources/KeyboardLayouts/*.json` (42 files)

**参考 VirtualBox devhid.cpp 的映射方法：**

每个 HID Usage ID 对应一个物理位置，不同布局在该位置放置不同字符。

**关键布局特征：**

1. **US (US QWERTY)** - 基准布局
2. **UK** - £在3键Shift，@/"交换，#在左Shift旁
3. **DE (QWERTZ)** - Z/Y交换，ßäöü，AltGr
4. **FR (AZERTY)** - A/Z交换，Q/A交换，数字需Shift，AltGr
5. **ES** - Ñ键，¿¡，ªº
6. **IT** - òàèéìù，AltGr
7. **PT** - çÇãõ，AltGr
8. **JP (JIS)** - 半角/全角、変換、無変換、Ro、¥、@
9. **BE** - 类似FR但有差异
10. **CH** - üöä§，AltGr
11. **Nordic** - åäö，AltGr
12. **CA** - 与US一致
13. **AU** - 与UK一致
14. **CN** - 与US一致

- [ ] **Step 1: 创建 US 布局 JSON（基准）**

创建完整的 `us_windows.json`, `us_macos.json`, `us_linux.json`

- [ ] **Step 2: 创建 UK 布局 JSON**

创建 `uk_windows.json`, `uk_macos.json`, `uk_linux.json`

- [ ] **Step 3: 创建 DE 布局 JSON**

创建 `de_windows.json`, `de_macos.json`, `de_linux.json`

- [ ] **Step 4: 创建 FR 布局 JSON**

创建 `fr_windows.json`, `fr_macos.json`, `fr_linux.json`

- [ ] **Step 5-10: 创建剩余布局 JSON**

ES, IT, PT, JP, BE, CH, Nordic, CA, AU, CN

- [ ] **Step 11: 验证所有 JSON 文件格式正确**

```bash
for file in Resources/KeyboardLayouts/*.json; do
  python3 -m json.tool "$file" > /dev/null || echo "Invalid: $file"
done
```

- [ ] **Step 12: 提交所有 JSON 文件**

```bash
git add Resources/KeyboardLayouts/
git commit -m "feat: add JSON keyboard layout definitions for all locales"
```

---

### Task 2.3: 重构 KeyboardLayoutBuilders 使用 JSON 加载器

**Files:**
- Modify: `KeyCmd/Managers/KeyboardLayoutBuilders.swift`

- [ ] **Step 1: 重构 WindowsLayoutBuilder**

```swift
struct WindowsLayoutBuilder {
    static func build(for locale: KeyboardLocale) -> KeyboardLayoutDefinition {
        do {
            return try KeyboardLayoutLoader.load(locale: locale, targetOS: .windows)
        } catch {
            // 回退到硬编码的 US 布局
            return buildFallbackUSLayout()
        }
    }
    
    private static func buildFallbackUSLayout() -> KeyboardLayoutDefinition {
        // 保留原有的硬编码 US 布局作为 fallback
        // ...
    }
}
```

- [ ] **Step 2: 重构 MacLayoutBuilder 和 LinuxLayoutBuilder**

```swift
struct MacLayoutBuilder {
    static func build(for locale: KeyboardLocale) -> KeyboardLayoutDefinition {
        do {
            return try KeyboardLayoutLoader.load(locale: locale, targetOS: .macos)
        } catch {
            return WindowsLayoutBuilder.build(for: locale)
        }
    }
}

struct LinuxLayoutBuilder {
    static func build(for locale: KeyboardLocale) -> KeyboardLayoutDefinition {
        do {
            return try KeyboardLayoutLoader.load(locale: locale, targetOS: .linux)
        } catch {
            return WindowsLayoutBuilder.build(for: locale)
        }
    }
}
```

- [ ] **Step 3: 删除原有的硬编码布局构建函数**

删除 `buildUsLayout()`, `buildUkLayout()`, `buildDeLayout()` 等所有硬编码函数

- [ ] **Step 4: 运行测试验证并提交**

---

### Task 2.4: 布局定义单元测试

**Files:**
- Test: `KeyCmdTests/KeyboardLayoutDefinitionTests.swift`

- [ ] **Step 1: 编写完整结构验证测试**

```swift
func testAllLayoutsStructure() {
    let locales: [KeyboardLocale] = KeyboardLocale.allCases
    let oses: [TargetOS] = [.windows, .macos, .linux]
    
    for locale in locales {
        for os in oses {
            do {
                let layout = try KeyboardLayoutLoader.load(locale: locale, targetOS: os)
                
                XCTAssertEqual(layout.locale, locale)
                XCTAssertEqual(layout.targetOS, os)
                XCTAssertGreaterThan(layout.rows.count, 0)
                
                // 验证所有键都有 HID Usage ID
                for row in layout.rows {
                    for keyDef in row {
                        XCTAssertNotNil(keyDef.hidUsageID, "Layout \(locale) \(os): key \(keyDef.keyName) missing HID Usage ID")
                    }
                }
                
                // 验证 metadata
                XCTAssertFalse(layout.metadata.name.isEmpty)
                XCTAssertEqual(layout.metadata.physicalStandard, locale.physicalStandard)
            } catch {
                XCTFail("Failed to load layout \(locale) \(os): \(error)")
            }
        }
    }
}
```

- [ ] **Step 2: 运行所有布局测试**

Run: `xcodebuild test -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/KeyboardLayoutDefinitionTests/testAllLayoutsStructure`
Expected: 42种组合全部通过

---

## 阶段 3：布局检测机制

### Task 3.1: 实现 iOS 活动键盘检测

**Files:**
- Modify: `KeyCmd/KeyboardLocale.swift`

**Interfaces:**
- Produces: `KeyboardLocale.detectActiveKeyboardLayout()` 静态方法

- [ ] **Step 1: 扩展 KeyboardLocale 添加检测方法**

```swift
// 在 KeyboardLocale.swift 中添加

extension KeyboardLocale {
    /// 检测iOS设备当前使用的键盘布局
    static func detectActiveKeyboardLayout() -> KeyboardLocale? {
        #if os(iOS)
        // 使用UITextInputMode检测当前键盘布局
        if let inputMode = UITextInputMode.activeInputMode {
            let languageCode = inputMode.primaryLanguage
            return mapLanguageCodeToLocale(languageCode)
        }
        #elseif os(macOS)
        // macOS使用TIS API检测当前输入源
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            if let layoutId = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let layoutIdString = Unmanaged<CFString>.fromOpaque(layoutId).takeUnretainedValue() as String
                return mapInputSourceIDToLocale(layoutIdString)
            }
        }
        #endif
        
        return nil
    }
    
    /// 将语言代码映射到KeyboardLocale
    private static func mapLanguageCodeToLocale(_ languageCode: String?) -> KeyboardLocale? {
        guard let code = languageCode else { return nil }
        
        let langCode = code.components(separatedBy: "-").first ?? code
        
        switch langCode {
        case "en":
            if code.contains("GB") || code.contains("UK") { return .uk }
            else if code.contains("AU") { return .au }
            else if code.contains("CA") { return .ca }
            return .us
        case "de": return .de
        case "fr": return .fr
        case "es": return .es
        case "it": return .it
        case "pt": return .pt
        case "ja": return .jp
        case "zh": return .cn
        case "sv", "no", "da", "fi": return .nordic
        case "nl":
            if code.contains("BE") { return .be }
            return .us
        default: return .us
        }
    }
    
    /// 将macOS输入源ID映射到KeyboardLocale
    private static func mapInputSourceIDToLocale(_ inputSourceID: String) -> KeyboardLocale? {
        if inputSourceID.contains("US") { return .us }
        if inputSourceID.contains("German") { return .de }
        if inputSourceID.contains("French") { return .fr }
        if inputSourceID.contains("Spanish") { return .es }
        if inputSourceID.contains("Italian") { return .it }
        if inputSourceID.contains("Portuguese") { return .pt }
        if inputSourceID.contains("Japanese") { return .jp }
        if inputSourceID.contains("Chinese") { return .cn }
        if inputSourceID.contains("British") { return .uk }
        if inputSourceID.contains("Nordic") { return .nordic }
        if inputSourceID.contains("Swiss") { return .ch }
        if inputSourceID.contains("Belgian") { return .be }
        return nil
    }
}
```

---

### Task 3.2: 实现 macOS 输入源检测

**Files:**
- Modify: `KeyCmd/KeyboardLocale.swift` (已在 Task 3.1 中完成)

**Note:** macOS 部分已在 Task 3.1 中实现，需要导入 Carbon.framework

---

### Task 3.3: 集成到 KeyboardLayoutManager

**Files:**
- Modify: `KeyCmd/Managers/KeyboardLayoutManager.swift`

- [ ] **Step 1: 修改 setupKeyboardLayoutDetection()**

```swift
// 在 KeyboardLayoutManager.swift 中

private func setupKeyboardLayoutDetection() {
    // 1. 首先尝试检测当前活动的键盘布局
    if let detectedLayout = KeyboardLocale.detectActiveKeyboardLayout() {
        currentKeyboardLocale = detectedLayout
        logger.log("Detected active keyboard layout: \(detectedLayout.rawValue)", category: "Keyboard")
        return
    }
    
    // 2. 如果检测失败，使用系统区域设置
    if autoDetectLocale {
        currentKeyboardLocale = KeyboardLocale.fromSystemLocale()
        logger.log("Using system locale: \(currentKeyboardLocale.rawValue)", category: "Keyboard")
    }
    
    // 3. 监听键盘布局变化（iOS）
    #if os(iOS)
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleKeyboardLayoutChanged),
        name: UITextInputMode.currentInputModeDidChangeNotification,
        object: nil
    )
    #endif
}

#if os(iOS)
@objc private func handleKeyboardLayoutChanged() {
    if autoDetectLocale, let detected = KeyboardLocale.detectActiveKeyboardLayout() {
        if detected != currentKeyboardLocale {
            currentKeyboardLocale = detected
            logger.log("Keyboard layout changed to: \(detected.rawValue)", category: "Keyboard")
            objectWillChange.send()
        }
    }
}
#endif
```

---

### Task 3.4: 布局检测集成测试

**Files:**
- Test: `KeyCmdTests/KeyboardLayoutDetectionTests.swift`

---

## 阶段 4：修饰键与死键处理

### Task 4.1: 修改 KeyboardManager 使用 KeyboardState

**Files:**
- Modify: `KeyCmd/Managers/KeyboardManager.swift`

- [ ] **Step 1: 集成 KeyboardState 到按键处理流程**

```swift
// 在 KeyboardManager.swift 中

func handleKeyPress(keyDef: KeyDefinition) {
    // 1. 检查是否是修饰键
    if keyDef.keyType == .modifier {
        KeyboardState.shared.updateModifierState(key: keyDef.hidUsageID, pressed: true)
        sendHIDReport(modifierByte: KeyboardState.shared.modifierByte, keyCodes: [])
        return
    }
    
    // 2. 检查是否是死键
    if isDeadKey(keyDef) {
        KeyboardState.shared.setDeadKey(deadKeyForDefinition(keyDef))
        return
    }
    
    // 3. 处理死键组合
    if let pendingDeadKey = KeyboardState.shared.pendingDeadKey {
        if let combinedChar = pendingDeadKey.combine(with: Character(keyDef.label)) {
            sendUnicodeCharacter(combinedChar)
            KeyboardState.shared.setDeadKey(nil)
            return
        }
        KeyboardState.shared.setDeadKey(nil)
    }
    
    // 4. 根据修饰键状态选择正确的字符
    let charToSend: String
    if KeyboardState.shared.isAltGrPressed, let altGrLabel = keyDef.altGrLabel {
        charToSend = altGrLabel
    } else if KeyboardState.shared.isShiftPressed, let shiftLabel = keyDef.shiftLabel {
        charToSend = shiftLabel
    } else {
        charToSend = keyDef.label
    }
    
    // 5. 发送HID报告
    sendHIDReport(modifierByte: KeyboardState.shared.modifierByte, keyCodes: [keyDef.hidUsageValue])
}

func handleKeyRelease(keyDef: KeyDefinition) {
    if keyDef.keyType == .modifier {
        KeyboardState.shared.updateModifierState(key: keyDef.hidUsageID, pressed: false)
        sendHIDReport(modifierByte: KeyboardState.shared.modifierByte, keyCodes: [])
    }
}

private func isDeadKey(_ keyDef: KeyDefinition) -> Bool {
    let deadKeyChars: Set<String> = ["´", "`", "^", "¨", "~"]
    return deadKeyChars.contains(keyDef.label) || keyDef.altGrLabel != nil
}

private func deadKeyForDefinition(_ keyDef: KeyDefinition) -> DeadKey? {
    switch keyDef.label {
    case "´": return .acute
    case "`": return .grave
    case "^": return .circumflex
    case "¨": return .diaeresis
    case "~": return .tilde
    default: return nil
    }
}
```

---

### Task 4.2-4.5: 实现字符选择、死键组合、AltGr支持、UnicodeManager更新

**Files:**
- Modify: `KeyCmd/Managers/KeyboardManager.swift`, `KeyCmd/Managers/UnicodeManager.swift`

---

### Task 4.6: 修饰键/死键集成测试

**Files:**
- Test: `KeyCmdTests/KeyboardModifierTests.swift`

---

## 阶段 5：端到端测试与优化

### Task 5.1: 完整流程集成测试

**Files:**
- Test: `KeyCmdTests/KeyboardFullFlowTests.swift`

### Task 5.2: 真机测试验证

**产出物:** 真机测试报告

### Task 5.3: 性能基准测试

**产出物:** 性能测试报告

### Task 5.4: 回归测试

**产出物:** 回归测试报告

### Task 5.5: 文档更新与代码清理

**Files:**
- Modify: README、注释、废弃代码清理
