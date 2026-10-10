# Keyboard Layout JSON Schema Design

> 设计日期：2026-10-10  
> 版本：1.0  
> 状态：设计完成，待实现

---

## 1. 设计目标

### 1.1 核心问题

当前键盘布局定义存在以下问题：

1. **硬编码布局**：所有布局在 Swift 代码中硬编码，修改需要重新编译
2. **映射不完整**：许多布局只基于 US 布局简单修改，缺少完整字符映射
3. **缺乏标准化**：没有使用国际标准（USB HID Usage ID）作为键码表示
4. **修饰键处理缺失**：无法正确处理 AltGr、死键等组合键

### 1.2 设计原则

借鉴 VirtualBox 的 `devhid.cpp` 方法，设计一个灵活、可扩展的 JSON 布局系统：

1. **数据驱动**：布局定义与代码分离，支持动态加载
2. **标准化**：使用 USB HID Usage ID 作为统一的键码表示
3. **完整性**：为每个 HID Usage ID 定义完整的字符映射
4. **可扩展性**：支持新布局、新特性的添加

---

## 2. JSON Schema 设计

### 2.1 顶层结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Keyboard Layout Definition",
  "description": "Defines a complete keyboard layout with character mappings for all HID Usage IDs",
  "type": "object",
  "properties": {
    "locale": {
      "type": "string",
      "enum": ["us", "uk", "de", "fr", "es", "it", "pt", "jp", "cn", "ca", "au", "be", "ch", "nordic"],
      "description": "Keyboard locale identifier"
    },
    "targetOS": {
      "type": "string",
      "enum": ["windows", "macos", "linux"],
      "description": "Target operating system for this layout"
    },
    "metadata": {
      "$ref": "#/definitions/metadata"
    },
    "keys": {
      "type": "array",
      "items": {
        "$ref": "#/definitions/keyDefinition"
      },
      "description": "Array of all key definitions in this layout"
    }
  },
  "required": ["locale", "targetOS", "metadata", "keys"]
}
```

### 2.2 Metadata 定义

```json
{
  "metadata": {
    "type": "object",
    "properties": {
      "name": {
        "type": "string",
        "description": "Human-readable layout name (e.g., 'German QWERTZ')"
      },
      "description": {
        "type": "string",
        "description": "Detailed description of the layout"
      },
      "physicalStandard": {
        "type": "string",
        "enum": ["ansi", "iso", "jis"],
        "description": "Physical keyboard standard"
      },
      "hasAltGr": {
        "type": "boolean",
        "default": false,
        "description": "Whether this layout uses AltGr key"
      },
      "version": {
        "type": "string",
        "description": "Layout version (e.g., '1.0.0')"
      },
      "author": {
        "type": "string",
        "description": "Layout author or maintainer"
      }
    },
    "required": ["name", "physicalStandard"]
  }
}
```

### 2.3 KeyDefinition 定义

```json
{
  "keyDefinition": {
    "type": "object",
    "properties": {
      "hidUsageID": {
        "type": "integer",
        "minimum": 0,
        "maximum": 255,
        "description": "USB HID Usage ID (Usage Page 0x07: Keyboard/Keypad)"
      },
      "keyName": {
        "type": "string",
        "description": "Internal identifier (e.g., 'q', '1', 'Shift')"
      },
      "label": {
        "type": "string",
        "description": "Base character displayed on the key"
      },
      "shiftLabel": {
        "type": "string",
        "description": "Character when Shift is pressed"
      },
      "altGrLabel": {
        "type": "string",
        "description": "Character when AltGr is pressed"
      },
      "deadKey": {
        "type": "string",
        "enum": ["acute", "grave", "circumflex", "diaeresis", "tilde", "ring", "macron", "breve", "dotabove", "cedilla", "ogonek", "caron"],
        "description": "If this key is a dead key, specifies the dead key type"
      },
      "keyType": {
        "type": "string",
        "enum": ["regular", "modifier", "special", "function", "navigation", "numpad"],
        "default": "regular",
        "description": "Type of key"
      },
      "width": {
        "type": "number",
        "minimum": 0.5,
        "default": 1.0,
        "description": "Key width multiplier (e.g., 1.5 for wide Shift)"
      },
      "row": {
        "type": "integer",
        "minimum": 0,
        "description": "Physical row position (0-based)"
      },
      "column": {
        "type": "integer",
        "minimum": 0,
        "description": "Physical column position (0-based)"
      },
      "description": {
        "type": "string",
        "description": "Optional description or note about this key"
      }
    },
    "required": ["hidUsageID", "keyName", "label", "row", "column"]
  }
}
```

---

## 3. 与 VirtualBox devhid.cpp 的对应关系

### 3.1 VirtualBox 的设计

VirtualBox 在 `devhid.cpp` 中使用静态数组映射 HID Usage ID 到 Linux keycode：

```cpp
// VirtualBox: src/VBox/Devices/USB/devhid.cpp
static const uint16_t s_ausKeyMap[256] = {
    [0x04] = KEY_A,           // HID Usage: Keyboard a and A
    [0x05] = KEY_B,           // HID Usage: Keyboard b and B
    [0x06] = KEY_C,           // HID Usage: Keyboard c and C
    [0x1E] = KEY_1,           // HID Usage: Keyboard 1 and !
    [0x1F] = KEY_2,           // HID Usage: Keyboard 2 and @
    // ... 完整映射约200+条目
};
```

### 3.2 KeyCmd 的改进

我们的 JSON schema 借鉴了 VirtualBox 的设计，但做了以下改进：

| 方面 | VirtualBox | KeyCmd JSON Schema |
|------|-----------|-------------------|
| **数据格式** | C++ 静态数组 | JSON 文件 |
| **映射目标** | Linux keycode | 字符标签 + HID Usage ID |
| **布局支持** | 单一映射表 | 每个布局独立定义 |
| **修饰键处理** | 基础支持 | 完整的 Shift/AltGr/Dead key |
| **可扩展性** | 需要重新编译 | 动态加载 JSON |

### 3.3 对应关系示例

**VirtualBox 的映射**：
```cpp
[0x14] = KEY_Q,  // HID 0x14 -> Linux KEY_Q
```

**KeyCmd JSON 的对应**：
```json
{
  "hidUsageID": 20,  // 0x14
  "keyName": "q",
  "label": "q",
  "shiftLabel": "Q",
  "row": 2,
  "column": 1
}
```

**关键区别**：
- VirtualBox 映射到 Linux keycode（内核使用）
- KeyCmd 映射到字符标签（用户界面使用）
- KeyCmd 额外记录物理位置（row, column）

---

## 4. HID Usage ID 映射规则

### 4.1 字母键 (0x04 - 0x1D)

```json
{
  "hidUsageID": 4,
  "keyName": "a",
  "label": "a",
  "shiftLabel": "A",
  "row": 3,
  "column": 1
}
```

**规则**：
- `label` 是小写字母
- `shiftLabel` 是大写字母
- 所有布局的字母键 HID Usage ID 相同，但物理位置可能不同（如德语 Z/Y 交换）

### 4.2 数字键 (0x1E - 0x27)

**US 布局示例**：
```json
{
  "hidUsageID": 30,
  "keyName": "1",
  "label": "1",
  "shiftLabel": "!",
  "row": 1,
  "column": 1
}
```

**德语布局示例**：
```json
{
  "hidUsageID": 30,
  "keyName": "1",
  "label": "1",
  "shiftLabel": "!",
  "row": 1,
  "column": 1
}
```

**规则**：
- 数字键的 HID Usage ID 在所有布局中相同
- `shiftLabel` 因布局而异（如德语 2 的 shift 是 `"` 而不是 `@`）

### 4.3 控制键 (0x28 - 0x3F)

```json
{
  "hidUsageID": 40,
  "keyName": "Enter",
  "label": "Enter",
  "keyType": "special",
  "row": 3,
  "column": 13
}
```

**规则**：
- 控制键通常没有 `shiftLabel` 或 `altGrLabel`
- `keyType` 设为 `"special"` 或 `"navigation"`

### 4.4 修饰键 (0xE0 - 0xE7)

```json
{
  "hidUsageID": 225,
  "keyName": "LeftShift",
  "label": "Shift",
  "keyType": "modifier",
  "width": 1.5,
  "row": 5,
  "column": 0
}
```

**规则**：
- `keyType` 必须为 `"modifier"`
- 没有 `shiftLabel` 或 `altGrLabel`
- `width` 通常为 1.5 或 2.0

### 4.5 特殊符号键

**US 布局的 Grave Accent**：
```json
{
  "hidUsageID": 53,
  "keyName": "GraveAccent",
  "label": "`",
  "shiftLabel": "~",
  "row": 1,
  "column": 0
}
```

**德语布局的 Grave Accent**：
```json
{
  "hidUsageID": 53,
  "keyName": "GraveAccent",
  "label": "^",
  "shiftLabel": "°",
  "deadKey": "circumflex",
  "row": 1,
  "column": 0
}
```

**规则**：
- 同一物理位置的键，不同布局有不同的字符映射
- 德语的 `^` 是死键，需要标记 `deadKey`

---

## 5. 死键（Dead Key）处理

### 5.1 死键的概念

死键是一种特殊键，按下后不立即产生字符，而是修改下一个按键的字符。例如：

- 法语布局：按下 `^`（死键），然后按 `e`，生成 `ê`
- 德语布局：按下 `´`（死键），然后按 `e`，生成 `é`

### 5.2 JSON 中的死键定义

```json
{
  "hidUsageID": 53,
  "keyName": "GraveAccent",
  "label": "^",
  "shiftLabel": "°",
  "deadKey": "circumflex",
  "row": 1,
  "column": 0
}
```

**规则**：
- `deadKey` 字段标识这是一个死键
- 枚举值对应不同的死键类型：
  - `acute`：´（锐音）
  - `grave`：`（重音）
  - `circumflex`：^（ circumflex）
  - `diaeresis`：¨（分音）
  - `tilde`：~（波浪号）
  - `ring`：˚（圆圈）
  - `macron`：¯（长音）
  - `breve`：˘（短音）
  - `dotabove`：˙（上点）
  - `cedilla`：¸（下钩）
  - `ogonek`：˛（小钩）
  - `caron`：ˇ（倒 circumflex）

### 5.3 死键组合规则

死键与基础字符的组合由运行时逻辑处理，不在 JSON 中定义。示例：

```
circumflex + e = ê
circumflex + a = â
acute + e = é
grave + e = è
diaeresis + e = ë
tilde + n = ñ
```

---

## 6. AltGr 组合处理

### 6.1 AltGr 的概念

AltGr（Right Alt）是欧洲键盘常用的修饰键，用于输入特殊字符。例如：

- 德语：AltGr + Q = @
- 法语：AltGr + E = €
- 西班牙语：AltGr + 2 = @

### 6.2 JSON 中的 AltGr 定义

```json
{
  "hidUsageID": 20,
  "keyName": "q",
  "label": "q",
  "shiftLabel": "Q",
  "altGrLabel": "@",
  "row": 2,
  "column": 1
}
```

**规则**：
- `altGrLabel` 字段定义 AltGr 组合的字符
- 只有 `metadata.hasAltGr` 为 `true` 的布局才使用 AltGr
- AltGr 组合优先于 Shift 组合

### 6.3 AltGr 优先级

当多个修饰键同时按下时，优先级为：

1. **AltGr** > Shift > 基础字符
2. 如果 `altGrLabel` 存在，使用它
3. 否则，如果 Shift 按下且 `shiftLabel` 存在，使用 `shiftLabel`
4. 否则，使用 `label`

---

## 7. 完整布局示例

### 7.1 US 布局（简化版）

```json
{
  "locale": "us",
  "targetOS": "windows",
  "metadata": {
    "name": "US QWERTY",
    "description": "Standard US QWERTY layout",
    "physicalStandard": "ansi",
    "hasAltGr": false,
    "version": "1.0.0"
  },
  "keys": [
    {
      "hidUsageID": 41,
      "keyName": "GraveAccent",
      "label": "`",
      "shiftLabel": "~",
      "row": 1,
      "column": 0
    },
    {
      "hidUsageID": 30,
      "keyName": "1",
      "label": "1",
      "shiftLabel": "!",
      "row": 1,
      "column": 1
    },
    {
      "hidUsageID": 20,
      "keyName": "q",
      "label": "q",
      "shiftLabel": "Q",
      "row": 2,
      "column": 1
    },
    {
      "hidUsageID": 4,
      "keyName": "a",
      "label": "a",
      "shiftLabel": "A",
      "row": 3,
      "column": 1
    },
    {
      "hidUsageID": 225,
      "keyName": "LeftShift",
      "label": "Shift",
      "keyType": "modifier",
      "width": 1.5,
      "row": 5,
      "column": 0
    }
  ]
}
```

### 7.2 德语布局（简化版）

```json
{
  "locale": "de",
  "targetOS": "windows",
  "metadata": {
    "name": "German QWERTZ",
    "description": "German QWERTZ layout with Z/Y swapped and special characters",
    "physicalStandard": "iso",
    "hasAltGr": true,
    "version": "1.0.0"
  },
  "keys": [
    {
      "hidUsageID": 53,
      "keyName": "GraveAccent",
      "label": "^",
      "shiftLabel": "°",
      "deadKey": "circumflex",
      "row": 1,
      "column": 0
    },
    {
      "hidUsageID": 31,
      "keyName": "2",
      "label": "2",
      "shiftLabel": "\"",
      "altGrLabel": "²",
      "row": 1,
      "column": 2
    },
    {
      "hidUsageID": 28,
      "keyName": "z",
      "label": "z",
      "shiftLabel": "Z",
      "row": 2,
      "column": 6
    },
    {
      "hidUsageID": 20,
      "keyName": "q",
      "label": "q",
      "shiftLabel": "Q",
      "altGrLabel": "@",
      "row": 2,
      "column": 1
    },
    {
      "hidUsageID": 224,
      "keyName": "RightAlt",
      "label": "AltGr",
      "keyType": "modifier",
      "row": 5,
      "column": 6
    }
  ]
}
```

---

## 8. 实现指南

### 8.1 加载 JSON 布局

```swift
struct KeyboardLayoutLoader {
    static func loadLayout(locale: KeyboardLocale, targetOS: TargetOS) throws -> KeyboardLayoutDefinition {
        let filename = "\(locale.rawValue)_\(targetOS.rawValue).json"
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else {
            throw LayoutError.fileNotFound(filename)
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let layoutDTO = try decoder.decode(KeyboardLayoutDTO.self, from: data)
        
        return KeyboardLayoutDefinition(from: layoutDTO)
    }
}
```

### 8.2 转换为 KeyboardLayoutDefinition

```swift
extension KeyboardLayoutDefinition {
    init(from dto: KeyboardLayoutDTO) {
        let metadata = LayoutMetadata(
            name: dto.metadata.name,
            description: dto.metadata.description,
            physicalStandard: PhysicalStandard(rawValue: dto.metadata.physicalStandard) ?? .ansi,
            hasAltGr: dto.metadata.hasAltGr ?? false
        )
        
        let rows = groupKeysIntoRows(dto.keys)
        
        self.init(
            locale: KeyboardLocale(rawValue: dto.locale) ?? .us,
            targetOS: TargetOS(rawValue: dto.targetOS) ?? .windows,
            rows: rows,
            metadata: metadata
        )
    }
}
```

### 8.3 使用翻译表

```swift
let layout = try KeyboardLayoutLoader.loadLayout(locale: .de, targetOS: .windows)
let table = KeyboardTranslationTable(layout: layout)

// 查找 HID Usage ID
let hid = table.hidUsageID(forCharacter: "ä")  // 返回 .keyboardSemicolon

// 查找物理位置
let position = table.position(forHID: .keyboardY)  // 返回 (row: 2, column: 6)
```

---

## 9. 验证规则

### 9.1 Schema 验证

使用 JSON Schema 验证工具检查布局文件：

```bash
# 使用 ajv (Another JSON Validator)
ajv validate -s keyboard-layout-schema.json -d layouts/de_windows.json
```

### 9.2 业务规则验证

1. **HID Usage ID 唯一性**：每个布局中，`hidUsageID` 必须唯一
2. **物理位置唯一性**：每个布局中，`(row, column)` 组合必须唯一
3. **修饰键完整性**：必须包含所有必要的修饰键（LeftShift, RightShift, LeftCtrl, RightCtrl, LeftAlt, RightAlt, LeftGUI, RightGUI）
4. **死键一致性**：如果 `deadKey` 字段存在，`keyType` 应为 `"regular"` 或 `"special"`

---

## 10. 未来扩展

### 10.1 支持的布局

当前计划支持 14 个布局：

- us, uk, de, fr, es, it, pt, jp, cn, ca, au, be, ch, nordic

### 10.2 可能的扩展

1. **自定义布局**：允许用户创建自定义布局
2. **布局变体**：支持同一布局的多个变体（如 US International）
3. **宏定义**：支持按键宏（如一键输入常用短语）
4. **多语言支持**：在 JSON 中添加多语言标签

---

## 11. 参考资源

1. **USB HID Usage Tables 1.12**
   - https://usb.org/sites/default/files/documents/hut1_12v2.pdf

2. **VirtualBox 源代码**
   - https://github.com/VirtualBox/virtualbox
   - src/VBox/Devices/USB/devhid.cpp

3. **JSON Schema 规范**
   - https://json-schema.org/specification.html

---

*文档完成于 2026-10-10*
