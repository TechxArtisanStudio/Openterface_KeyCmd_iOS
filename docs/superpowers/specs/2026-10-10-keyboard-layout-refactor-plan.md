# KeyCmd 多国键盘布局重构计划

> 日期：2026-10-10  
> 目标：解决键盘按钮匹配不准确的问题，借鉴VirtualBox的键盘架构设计

---

## 1. 当前问题分析

### 1.1 布局检测不准确

**问题**：
```swift
// KeyboardLocale.swift
static func fromSystemLocale() -> KeyboardLocale {
    let currentLocale = Locale.current
    // ...
}
```

**问题点**：
- `Locale.current`反映的是系统区域设置，不是实际使用的键盘布局
- 例如：中国用户使用美式键盘，系统区域是"zh-CN"，但键盘应该是US布局
- 用户可能在系统设置中切换了键盘布局，但`Locale.current`不会更新

**影响**：
- 自动检测经常选择错误的布局
- 用户需要手动切换布局，体验差

### 1.2 键名到HID码映射不一致

**问题**：
```swift
// KeyboardLayoutManager.swift
func hidKeyName(for keyName: String) -> String {
    if keyName == "Esc" { return "Escape" }
    let keyDef = currentLayout.keyDefinition(for: keyName)
    let resolved = keyDef?.keyCode ?? keyName
    
    // 硬编码的特殊情况
    if keyName == "¥" || keyName == "\\" || keyName == "@" || keyName == "^" || keyName == ":" {
        print("DEBUG...")
    }
    return resolved
}
```

**问题点**：
- 硬编码的特殊键映射不完整
- 这些映射只适用于某些布局，对其他布局可能不正确
- 缺少对AltGr组合键的处理
- 没有考虑修饰键状态（Shift、AltGr）

**影响**：
- 特殊字符无法正确发送
- 不同布局下相同位置的键可能产生错误的字符

### 1.3 布局定义基于US布局修改

**问题**：
```swift
// KeyboardLayoutBuilders.swift
private static func buildDeLayout() -> KeyboardLayoutDefinition {
    let usLayout = buildUsLayout()
    var rows = usLayout.rows
    
    // 只交换Z和Y
    // 缺少其他德语布局特有的字符映射
}
```

**问题点**：
- 很多布局只是基于US布局进行简单修改
- 缺少完整的字符映射表
- 没有考虑不同布局的特殊字符位置

**影响**：
- 德语布局缺少特殊字符（如ß、ä、ö、ü）
- 法语布局的AltGr字符可能不正确
- 北欧布局的特殊字符位置可能错误

### 1.4 缺少修饰键状态处理

**问题**：
```swift
// KeyDefinition.swift
struct KeyDefinition {
    let label: String           // 基础标签
    let shiftLabel: String?     // Shift标签
    let altGrLabel: String?     // AltGr标签
    // ...
}
```

**问题点**：
- 定义了修饰键标签，但没有使用它们
- 发送按键时没有考虑当前修饰键状态
- 无法正确处理需要修饰键组合的字符

**影响**：
- 无法输入需要AltGr的字符（如€、@在某些布局中）
- 无法正确处理死键组合

---

## 2. 重构方案

### 2.1 使用USB HID Usage ID作为标准

**目标**：统一键码表示，确保跨平台一致性

**实现**：

```swift
// 新增文件：HIDUsageID.swift

/// USB HID Usage IDs (Usage Page 0x07: Keyboard/Keypad)
/// 参考：USB HID Usage Tables 1.12
enum HIDUsageID: UInt8 {
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
    
    // 修饰键 (0xE0 - 0xE7)
    case keyboardLeftCtrl = 0xE0
    case keyboardLeftShift = 0xE1
    case keyboardLeftAlt = 0xE2
    case keyboardLeftGUI = 0xE3
    case keyboardRightCtrl = 0xE4
    case keyboardRightShift = 0xE5
    case keyboardRightAlt = 0xE6  // AltGr
    case keyboardRightGUI = 0xE7
    
    // 日语特殊键
    case keyboardInternational1 = 0x87  // Ro
    case keyboardInternational2 = 0x88  // かな
    case keyboardInternational3 = 0x89  // 変換
    case keyboardInternational4 = 0x8A  // 無変換
    case keyboardInternational5 = 0x8B  // katakana/hiragana
    // ... 更多键
}

extension HIDUsageID {
    /// 从物理位置获取HID Usage ID
    /// 这个方法不考虑布局，只考虑物理位置
    static func fromPhysicalPosition(row: Int, column: Int) -> HIDUsageID? {
        // 标准104键键盘的物理位置映射
        let positionMap: [[HIDUsageID?]] = [
            // 功能行
            [keyboardEscape, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
            // 数字行
            [keyboard1, keyboard2, keyboard3, keyboard4, keyboard5, keyboard6, keyboard7, keyboard8, keyboard9, keyboard0, keyboardMinus, keyboardEqual, keyboardBackspace, nil, nil, nil, nil, nil, nil, nil],
            // QWERTY行
            [keyboardTab, keyboardQ, keyboardW, keyboardE, keyboardR, keyboardT, keyboardY, keyboardU, keyboardI, keyboardO, keyboardP, keyboardLeftBracket, nil, nil, nil, nil, nil, nil, nil, nil],
            // ASDF行
            [keyboardA, keyboardS, keyboardD, keyboardF, keyboardG, keyboardH, keyboardJ, keyboardK, keyboardL, nil, nil, nil, keyboardEnter, nil, nil, nil, nil, nil, nil, nil],
            // ZXCV行
            [keyboardZ, keyboardX, keyboardC, keyboardV, keyboardB, keyboardN, keyboardM, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
            // 修饰键行
            [keyboardLeftCtrl, keyboardLeftAlt, keyboardSpace, keyboardRightAlt, keyboardRightCtrl, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
        ]
        
        guard row < positionMap.count, column < positionMap[row].count else { return nil }
        return positionMap[row][column]
    }
}
```

**优势**：
- 使用国际标准，确保一致性
- 物理位置与逻辑键码分离
- 便于跨平台映射

### 2.2 改进布局检测机制

**目标**：更准确地检测实际使用的键盘布局

**实现**：

```swift
// 扩展 KeyboardLocale.swift

extension KeyboardLocale {
    /// 检测iOS设备当前使用的键盘布局
    /// 这个方法比fromSystemLocale()更准确
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
        
        // 提取语言代码（例如："en-US" -> "en"）
        let langCode = code.components(separatedBy: "-").first ?? code
        
        switch langCode {
        case "en":
            // 英语需要进一步区分
            if code.contains("GB") || code.contains("UK") {
                return .uk
            } else if code.contains("AU") {
                return .au
            } else if code.contains("CA") {
                return .ca
            }
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
            if code.contains("BE") {
                return .be
            }
            return .us  // 荷兰语通常使用US布局
        default: return .us
        }
    }
    
    /// 将macOS输入源ID映射到KeyboardLocale
    private static func mapInputSourceIDToLocale(_ inputSourceID: String) -> KeyboardLocale? {
        // 示例输入源ID：
        // "com.apple.keylayout.US" -> .us
        // "com.apple.keylayout.German" -> .de
        // "com.apple.keylayout.French" -> .fr
        
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

**在KeyboardLayoutManager中使用**：

```swift
// KeyboardLayoutManager.swift

final class KeyboardLayoutManager: ObservableObject {
    // ...
    
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
            }
        }
    }
    #endif
}
```

### 2.3 重构KeyDefinition，使用HID Usage ID

**目标**：将键码标准化为USB HID Usage ID

**实现**：

```swift
// 修改 KeyDefinition.swift

struct KeyDefinition: Codable, Equatable, Hashable {
    let keyName: String                    // 内部标识符，如"q", "1", "Shift"
    let label: String                      // 显示标签
    let shiftLabel: String?                // Shift时的标签
    let altGrLabel: String?                // AltGr时的标签
    let hidUsageID: HIDUsageID             // USB HID Usage ID（新增）
    let keyType: KeyType
    let widthMultiplier: CGFloat?
    let heightMultiplier: CGFloat?
    
    init(keyName: String,
         label: String,
         shiftLabel: String? = nil,
         altGrLabel: String? = nil,
         hidUsageID: HIDUsageID,
         keyType: KeyType = .regular,
         widthMultiplier: CGFloat? = nil,
         heightMultiplier: CGFloat? = nil) {
        self.keyName = keyName
        self.label = label
        self.shiftLabel = shiftLabel
        self.altGrLabel = altGrLabel
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

// 辅助函数
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

**更新布局构建器示例**：

```swift
// KeyboardLayoutBuilders.swift

private static func buildUsLayout() -> KeyboardLayoutDefinition {
    let rows: [KeyRow] = [
        // 功能行
        [
            KeyDefinition.key("Esc", "Esc", hid: .keyboardEscape),
            KeyDefinition.key("F1", "F1", hid: .keyboardF1),
            // ...
        ],
        // 数字行
        [
            KeyDefinition.key("`", "`", shift: "~", hid: .keyboardGraveAccent),
            KeyDefinition.key("1", "1", shift: "!", hid: .keyboard1),
            KeyDefinition.key("2", "2", shift: "@", hid: .keyboard2),
            // ...
        ],
        // QWERTY行
        [
            KeyDefinition.key("Tab", "Tab", hid: .keyboardTab),
            KeyDefinition.key("q", "Q", hid: .keyboardQ),
            KeyDefinition.key("w", "W", hid: .keyboardW),
            KeyDefinition.key("e", "E", hid: .keyboardE),
            // ...
        ],
        // ...
    ]
    
    // ...
}

// 德语布局示例
private static func buildDeLayout() -> KeyboardLayoutDefinition {
    let rows: [KeyRow] = [
        // 功能行（与US相同）
        // ...
        
        // 数字行（德语特殊字符）
        [
            KeyDefinition.key("^", "^", shift: "°", hid: .keyboardGraveAccent),  // 德语的^键
            KeyDefinition.key("1", "1", shift: "!", hid: .keyboard1),
            KeyDefinition.key("2", "2", shift: "\"", hid: .keyboard2),  // 德语2的shift是"
            KeyDefinition.key("3", "3", shift: "§", hid: .keyboard3),   // 德语3的shift是§
            // ...
        ],
        
        // QWERTZ行（Z和Y交换）
        [
            KeyDefinition.key("Tab", "Tab", hid: .keyboardTab),
            KeyDefinition.key("q", "Q", hid: .keyboardQ),
            KeyDefinition.key("w", "W", hid: .keyboardW),
            KeyDefinition.key("e", "E", hid: .keyboardE),
            KeyDefinition.key("r", "R", hid: .keyboardR),
            KeyDefinition.key("t", "T", hid: .keyboardT),
            KeyDefinition.key("z", "Z", hid: .keyboardY),  // Z在Y的位置
            KeyDefinition.key("u", "U", hid: .keyboardU),
            // ...
        ],
        
        // ASDF行
        [
            KeyDefinition.key("Caps", "Caps", hid: .keyboardCapsLock),
            KeyDefinition.key("a", "A", hid: .keyboardA),
            KeyDefinition.key("s", "S", hid: .keyboardS),
            KeyDefinition.key("d", "D", hid: .keyboardD),
            KeyDefinition.key("f", "F", hid: .keyboardF),
            KeyDefinition.key("g", "G", hid: .keyboardG),
            KeyDefinition.key("h", "H", hid: .keyboardH),
            KeyDefinition.key("j", "J", hid: .keyboardJ),
            KeyDefinition.key("k", "K", hid: .keyboardK),
            KeyDefinition.key("l", "L", hid: .keyboardL),
            KeyDefinition.key("ö", "Ö", hid: .keyboardSemicolon),  // 德语的ö键
            KeyDefinition.key("ä", "Ä", hid: .keyboardQuote),       // 德语的ä键
            KeyDefinition.key("#", "'", hid: .keyboardBackslash),   // 德语的#键
            KeyDefinition.key("Enter", "Enter", hid: .keyboardEnter),
        ],
        
        // ZXCV行
        [
            KeyDefinition.mod("Shift", hid: .keyboardLeftShift, width: 1.5),
            KeyDefinition.key("y", "Y", hid: .keyboardZ),  // Y在Z的位置
            KeyDefinition.key("x", "X", hid: .keyboardX),
            KeyDefinition.key("c", "C", hid: .keyboardC),
            KeyDefinition.key("v", "V", hid: .keyboardV),
            KeyDefinition.key("b", "B", hid: .keyboardB),
            KeyDefinition.key("n", "N", hid: .keyboardN),
            KeyDefinition.key("m", "M", hid: .keyboardM),
            KeyDefinition.key(",", ",", shift: ";", hid: .keyboardComma),
            KeyDefinition.key(".", ".", shift: ":", hid: .keyboardPeriod),
            KeyDefinition.key("-", "_", hid: .keyboardMinus),
            KeyDefinition.mod("Shift", hid: .keyboardRightShift, width: 1.5),
        ],
        
        // 修饰键行
        [
            KeyDefinition.mod("Ctrl", hid: .keyboardLeftCtrl),
            KeyDefinition.mod("Win", hid: .keyboardLeftGUI),
            KeyDefinition.mod("Alt", hid: .keyboardLeftAlt),
            KeyDefinition.key("Space", " ", hid: .keyboardSpace, width: 6.0),
            KeyDefinition.mod("AltGr", hid: .keyboardRightAlt),  // 德语使用AltGr
            KeyDefinition.mod("Win", hid: .keyboardRightGUI),
            KeyDefinition.mod("Ctrl", hid: .keyboardRightCtrl),
        ]
    ]
    
    let metadata = LayoutMetadata(
        name: "German QWERTZ",
        description: "German QWERTZ layout with Z/Y swapped and special characters",
        rowHeights: [0.1, 0.1, 0.2, 0.2, 0.2, 0.2],
        keySpacing: 3,
        rowSpacing: 6,
        padding: LayoutPadding(top: 8, leading: 8, bottom: 8, trailing: 8),
        fixedKeyWidths: ["Space": 200],
        physicalStandard: .iso,
        hasAltGr: true
    )
    
    return KeyboardLayoutDefinition(
        locale: .de,
        targetOS: .windows,
        rows: rows,
        metadata: metadata
    )
}
```

### 2.4 实现修饰键状态感知

**目标**：正确处理需要修饰键组合的字符

**实现**：

```swift
// 新增文件：KeyboardState.swift

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
}

enum DeadKey {
    case acute       // ´
    case grave       // `
    case circumflex  // ^
    case diaeresis   // ¨
    case tilde       // ~
    
    /// 将死键与基础字符组合
    func combine(with baseChar: Character) -> Character? {
        // 实现死键组合逻辑
        // 例如：circumflex + e = ê
        switch (self, baseChar) {
        case (.circumflex, "e"): return "ê"
        case (.circumflex, "a"): return "â"
        case (.acute, "e"): return "é"
        case (.grave, "e"): return "è"
        // ... 更多组合
        default: return nil
        }
    }
}
```

**在按键处理中使用**：

```swift
// KeyboardManager.swift

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
            // 发送组合后的字符
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
```

### 2.5 优化翻译表设计

**目标**：使用哈希表提高查找效率

**实现**：

```swift
// 新增文件：KeyboardTranslationTable.swift

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
                charToH[Character(keyDef.label)] = keyDef.hidUsageID
                if let shiftLabel = keyDef.shiftLabel {
                    charToH[Character(shiftLabel)] = keyDef.hidUsageID
                }
                if let altGrLabel = keyDef.altGrLabel {
                    charToH[Character(altGrLabel)] = keyDef.hidUsageID
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

---

## 3. 实施步骤

### 阶段1：基础设施（1-2天）

1. **创建HIDUsageID枚举**
   - 定义所有USB HID Usage IDs
   - 添加物理位置映射

2. **修改KeyDefinition**
   - 添加hidUsageID字段
   - 更新所有构建器函数

3. **创建KeyboardState**
   - 实现修饰键状态跟踪
   - 实现死键状态管理

### 阶段2：布局重构（2-3天）

1. **重构US布局**
   - 为所有键添加HID Usage ID
   - 测试基础功能

2. **重构其他布局**
   - 德语、法语、西班牙语等
   - 确保特殊字符正确映射

3. **更新布局管理器**
   - 使用新的翻译表
   - 优化缓存机制

### 阶段3：布局检测（1天）

1. **实现iOS键盘检测**
   - 使用UITextInputMode API
   - 监听布局变化事件

2. **实现macOS键盘检测**
   - 使用TIS API
   - 处理输入源切换

3. **集成到KeyboardLayoutManager**
   - 优先使用活动键盘检测
   - 回退到系统区域检测

### 阶段4：修饰键处理（1-2天）

1. **实现修饰键状态感知**
   - 在按键处理中检查修饰键状态
   - 正确选择字符变体

2. **实现死键支持**
   - 检测死键
   - 实现死键组合逻辑

3. **实现AltGr支持**
   - 正确处理AltGr组合
   - 测试欧洲布局

### 阶段5：测试与优化（2天）

1. **单元测试**
   - 测试所有布局的键映射
   - 测试修饰键组合
   - 测试死键组合

2. **集成测试**
   - 测试实际按键发送
   - 测试布局切换
   - 测试跨平台兼容性

3. **性能优化**
   - 优化翻译表查找
   - 优化缓存策略

---

## 4. 预期效果

### 4.1 解决的问题

1. **布局检测不准确**
   - 通过检测活动键盘布局，而不是系统区域
   - 自动响应布局切换

2. **键码映射不一致**
   - 使用USB HID Usage ID作为标准
   - 消除硬编码的特殊情况

3. **特殊字符无法输入**
   - 正确处理修饰键组合
   - 支持AltGr和死键

4. **布局定义不完整**
   - 为每个布局创建完整的字符映射
   - 包含所有特殊字符

### 4.2 性能提升

1. **更快的查找**
   - 使用哈希表代替数组
   - O(1)查找复杂度

2. **更少的内存**
   - 标准化的键码表示
   - 高效的缓存机制

### 4.3 可维护性提升

1. **清晰的架构**
   - 物理位置与逻辑键码分离
   - 明确的职责划分

2. **易于扩展**
   - 添加新布局只需定义字符映射
   - 不需要修改核心逻辑

---

## 5. 风险与缓解

### 5.1 兼容性风险

**风险**：修改键码表示可能影响现有代码

**缓解**：
- 保持向后兼容的API
- 逐步迁移，而不是一次性重构
- 提供过渡期的兼容层

### 5.2 测试覆盖风险

**风险**：14个布局 × 3个操作系统 = 42种组合，测试工作量大

**缓解**：
- 优先测试常用布局（US、UK、DE、FR、JP）
- 使用自动化测试
- 基于VirtualBox的参考实现验证

### 5.3 性能风险

**风险**：额外的状态跟踪可能影响性能

**缓解**：
- 使用轻量级的状态管理
- 只在必要时更新状态
- 性能测试和优化

---

## 6. 参考资源

1. **USB HID Usage Tables 1.12**
   - https://usb.org/sites/default/files/documents/hut1_12v2.pdf

2. **VirtualBox源代码**
   - https://github.com/VirtualBox/virtualbox
   - src/VBox/Devices/Input/
   - src/VBox/Devices/USB/devhid.cpp

3. **iOS键盘API文档**
   - UITextInputMode: https://developer.apple.com/documentation/uikit/uitextinputmode

4. **macOS输入源API**
   - Text Input Source Services: https://developer.apple.com/documentation/carbondirectory/text_input_source_services

---

## 7. 总结

这次重构将解决当前多国键盘布局实现中的核心问题：

1. **标准化**：使用USB HID Usage ID作为统一的键码表示
2. **准确性**：改进布局检测机制，更准确地反映实际使用的键盘
3. **完整性**：为每个布局创建完整的字符映射，包括特殊字符
4. **智能性**：实现修饰键状态感知，正确处理组合键

通过借鉴VirtualBox的键盘架构设计，我们可以建立一个更可靠、更易维护的多国键盘布局系统。

---

*文档完成于 2026-10-10*
