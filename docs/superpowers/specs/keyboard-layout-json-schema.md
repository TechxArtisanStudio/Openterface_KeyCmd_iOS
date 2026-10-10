# 键盘布局 JSON Schema 设计规范

> 日期：2026-10-10  
> 目的：定义基于 JSON 的键盘布局格式，参考 VirtualBox 的 devhid.cpp 方法

---

## 1. 设计原则

### 1.1 核心理念

本 JSON Schema 设计遵循以下核心原则：

1. **以 HID Usage ID 为中心**：每个键的定义都基于 USB HID Usage ID，确保跨平台一致性
2. **物理位置与逻辑字符分离**：键的物理位置（row, column）与其显示的字符（label）解耦
3. **完整字符映射**：支持基础字符、Shift 字符、AltGr 字符的完整定义
4. **死键支持**：明确标识死键及其组合规则
5. **布局元数据**：包含物理标准（ANSI/ISO/JIS）、是否有 AltGr 等关键信息

### 1.2 与 VirtualBox devhid.cpp 的对应关系

VirtualBox 在 `devhid.cpp` 中使用静态数组映射 HID Usage ID 到 Linux keycode：

```cpp
// VirtualBox devhid.cpp 示例
static const uint16_t s_ausKeyMap[256] = {
    [0x04] = KEY_A,           // HID Usage: Keyboard a and A
    [0x05] = KEY_B,           // HID Usage: Keyboard b and B
    [0x1E] = KEY_1,           // HID Usage: Keyboard 1 and !
    // ...
};
```

**我们的 JSON 方案对应**：

| VirtualBox 概念 | JSON Schema 对应 | 说明 |
|----------------|-----------------|------|
| `s_ausKeyMap[usageId]` | `keys[].hidUsageID` | 每个键的 HID Usage ID |
| 物理位置（隐含在数组索引） | `keys[].row`, `keys[].column` | 显式定义物理位置 |
| 字符映射（由 Guest OS 处理） | `keys[].label`, `shiftLabel`, `altGrLabel` | 在布局文件中显式定义 |
| 死键处理（XKB 规则） | `keys[].deadKey` | 明确标识死键类型 |
| 布局检测（Guest Additions） | `metadata.physicalStandard`, `hasAltGr` | 布局元数据 |

**关键差异**：
- VirtualBox 依赖 Guest OS 的布局系统（XKB/Windows Keyboard Layout）
- 我们的方案在 JSON 中显式定义字符映射，不依赖操作系统
- 更适合硬件键盘模拟器场景

---

## 2. JSON Schema 详细定义

### 2.1 顶层结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Keyboard Layout Definition",
  "type": "object",
  "properties": {
    "locale": {
      "type": "string",
      "enum": ["us", "uk", "de", "fr", "es", "it", "pt", "jp", "cn", "ca", "au", "be", "ch", "nordic"],
      "description": "键盘布局的区域设置标识符"
    },
    "targetOS": {
      "type": "string",
      "enum": ["windows", "macos", "linux"],
      "description": "目标操作系统（影响某些特殊键的处理）"
    },
    "metadata": {
      "type": "object",
      "description": "布局元数据",
      "properties": {
        "name": {
          "type": "string",
          "description": "布局名称，如 'US QWERTY', 'German QWERTZ'"
        },
        "description": {
          "type": "string",
          "description": "布局的详细描述"
        },
        "physicalStandard": {
          "type": "string",
          "enum": ["ansi", "iso", "jis"],
          "description": "物理键盘标准"
        },
        "hasAltGr": {
          "type": "boolean",
          "description": "是否使用 AltGr 键（欧洲布局通常需要）"
        }
      },
      "required": ["name", "physicalStandard"]
    },
    "keys": {
      "type": "array",
      "description": "键定义数组",
      "items": {
        "$ref": "#/definitions/KeyDefinition"
      }
    }
  },
  "required": ["locale", "targetOS", "metadata", "keys"]
}
```

### 2.2 KeyDefinition 定义

```json
{
  "definitions": {
    "KeyDefinition": {
      "type": "object",
      "properties": {
        "hidUsageID": {
          "type": "integer",
          "minimum": 0,
          "maximum": 255,
          "description": "USB HID Usage ID（Usage Page 0x07: Keyboard/Keypad）"
        },
        "keyName": {
          "type": "string",
          "description": "内部标识符，如 'q', '1', 'Shift', 'Enter'"
        },
        "label": {
          "type": "string",
          "description": "基础标签（无修饰键时显示的字符）"
        },
        "shiftLabel": {
          "type": "string",
          "description": "Shift 修饰时的标签"
        },
        "altGrLabel": {
          "type": "string",
          "description": "AltGr 修饰时的标签"
        },
        "deadKey": {
          "type": "string",
          "enum": ["acute", "grave", "circumflex", "diaeresis", "tilde", "ring", "caron", "macron", "breve", "dot_above", "cedilla", "ogonek", "double_acute"],
          "description": "死键类型（如果该键是死键）"
        },
        "keyType": {
          "type": "string",
          "enum": ["regular", "modifier", "special"],
          "default": "regular",
          "description": "键类型"
        },
        "width": {
          "type": "number",
          "minimum": 0.5,
          "description": "键宽度（以标准键宽度为单位，1.0 = 标准键宽）"
        },
        "row": {
          "type": "integer",
          "minimum": 0,
          "description": "物理行号（0 = 功能行，1 = 数字行，2 = QWERTY 行，3 = ASDF 行，4 = ZXCV 行，5 = 修饰键行）"
        },
        "column": {
          "type": "integer",
          "minimum": 0,
          "description": "物理列号（从左到右，0 开始）"
        }
      },
      "required": ["hidUsageID", "keyName", "label", "row", "column"]
    }
  }
}
```

---

## 3. HID Usage ID 映射规则

### 3.1 字母键 (0x04 - 0x1D)

| HID Usage ID | 键名 | 说明 |
|-------------|------|------|
| 0x04 | keyboardA | Keyboard a and A |
| 0x05 | keyboardB | Keyboard b and B |
| 0x06 | keyboardC | Keyboard c and C |
| 0x07 | keyboardD | Keyboard d and D |
| 0x08 | keyboardE | Keyboard e and E |
| 0x09 | keyboardF | Keyboard f and F |
| 0x0A | keyboardG | Keyboard g and G |
| 0x0B | keyboardH | Keyboard h and H |
| 0x0C | keyboardI | Keyboard i and I |
| 0x0D | keyboardJ | Keyboard j and J |
| 0x0E | keyboardK | Keyboard k and K |
| 0x0F | keyboardL | Keyboard l and L |
| 0x10 | keyboardM | Keyboard m and M |
| 0x11 | keyboardN | Keyboard n and N |
| 0x12 | keyboardO | Keyboard o and O |
| 0x13 | keyboardP | Keyboard p and P |
| 0x14 | keyboardQ | Keyboard q and Q |
| 0x15 | keyboardR | Keyboard r and R |
| 0x16 | keyboardS | Keyboard s and S |
| 0x17 | keyboardT | Keyboard t and T |
| 0x18 | keyboardU | Keyboard u and U |
| 0x19 | keyboardV | Keyboard v and V |
| 0x1A | keyboardW | Keyboard w and W |
| 0x1B | keyboardX | Keyboard x and X |
| 0x1C | keyboardY | Keyboard y and Y |
| 0x1D | keyboardZ | Keyboard z and Z |

**重要**：HID Usage ID 表示物理位置，不是字符。例如：
- 德语 QWERTZ 布局中，Z 键在 Y 的位置，但 HID Usage ID 仍然是 0x1C (keyboardY)
- 法语 AZERTY 布局中，A 键在 Q 的位置，但 HID Usage ID 仍然是 0x04 (keyboardA)

### 3.2 数字键 (0x1E - 0x27)

| HID Usage ID | 键名 | US 布局基础字符 | US 布局 Shift 字符 |
|-------------|------|----------------|-------------------|
| 0x1E | keyboard1 | 1 | ! |
| 0x1F | keyboard2 | 2 | @ |
| 0x20 | keyboard3 | 3 | # |
| 0x21 | keyboard4 | 4 | $ |
| 0x22 | keyboard5 | 5 | % |
| 0x23 | keyboard6 | 6 | ^ |
| 0x24 | keyboard7 | 7 | & |
| 0x25 | keyboard8 | 8 | * |
| 0x26 | keyboard9 | 9 | ( |
| 0x27 | keyboard0 | 0 | ) |

### 3.3 控制键 (0x28 - 0x3F)

| HID Usage ID | 键名 | 说明 |
|-------------|------|------|
| 0x28 | keyboardEnter | Return (ENTER) |
| 0x29 | keyboardEscape | ESCAPE |
| 0x2A | keyboardBackspace | Backspace |
| 0x2B | keyboardTab | Tab |
| 0x2C | keyboardSpace | Spacebar |
| 0x2D | keyboardMinus | - and _ |
| 0x2E | keyboardEqual | = and + |
| 0x2F | keyboardLeftBracket | [ and { |
| 0x30 | keyboardRightBracket | ] and } |
| 0x31 | keyboardBackslash | \ and | |
| 0x33 | keyboardSemicolon | ; and : |
| 0x34 | keyboardQuote | ' and " |
| 0x35 | keyboardGraveAccent | ` and ~ |
| 0x36 | keyboardComma | , and < |
| 0x37 | keyboardPeriod | . and > |
| 0x38 | keyboardSlash | / and ? |
| 0x39 | keyboardCapsLock | Caps Lock |

### 3.4 功能键 (0x3A - 0x45)

| HID Usage ID | 键名 |
|-------------|------|
| 0x3A | keyboardF1 |
| 0x3B | keyboardF2 |
| 0x3C | keyboardF3 |
| 0x3D | keyboardF4 |
| 0x3E | keyboardF5 |
| 0x3F | keyboardF6 |
| 0x40 | keyboardF7 |
| 0x41 | keyboardF8 |
| 0x42 | keyboardF9 |
| 0x43 | keyboardF10 |
| 0x44 | keyboardF11 |
| 0x45 | keyboardF12 |

### 3.5 修饰键 (0xE0 - 0xE7)

| HID Usage ID | 键名 | 说明 |
|-------------|------|------|
| 0xE0 | keyboardLeftCtrl | Left Control |
| 0xE1 | keyboardLeftShift | Left Shift |
| 0xE2 | keyboardLeftAlt | Left Alt |
| 0xE3 | keyboardLeftGUI | Left GUI (Windows/Command) |
| 0xE4 | keyboardRightCtrl | Right Control |
| 0xE5 | keyboardRightShift | Right Shift |
| 0xE6 | keyboardRightAlt | Right Alt (AltGr) |
| 0xE7 | keyboardRightGUI | Right GUI |

### 3.6 国际键 (0x87 - 0x91)

| HID Usage ID | 键名 | 说明 |
|-------------|------|------|
| 0x87 | keyboardInternational1 | Ro (日语) |
| 0x88 | keyboardInternational2 | かな (日语) |
| 0x89 | keyboardInternational3 | 変換 (日语) |
| 0x8A | keyboardInternational4 | 無変換 (日语) |
| 0x8B | keyboardInternational5 | katakana/hiragana |
| 0x8C | keyboardInternational6 | = (numpad) |
| 0x8D | keyboardInternational7 | , (Thousand separator) |
| 0x8E | keyboardInternational8 | . (Decimal separator) |
| 0x8F | keyboardInternational9 | / |

---

## 4. 死键（Dead Keys）处理

### 4.1 死键类型

| 死键类型 | 符号 | 说明 | 示例组合 |
|---------|------|------|---------|
| acute | ´ | 尖音符 | acute + e = é |
| grave | ` | 重音符 | grave + e = è |
| circumflex | ^ |  circumflex | circumflex + e = ê |
| diaeresis | ¨ | 分音符 | diaeresis + e = ë |
| tilde | ~ | 波浪符 | tilde + n = ñ |
| ring | ° | 上圆圈 | ring + a = å |
| caron | ˇ | 卡龙符 | caron + c = č |
| macron | ¯ | 长音符 | macron + a = ā |
| breve | ˘ | 短音符 | breve + a = ă |
| dot_above | ˙ | 上点符 | dot_above + z = ż |
| cedilla | ¸ | 下钩符 | cedilla + c = ç |
| ogonek | ˛ | 下尾符 | ogonek + a = ą |
| double_acute | ˝ | 双尖符 | double_acute + o = ő |

### 4.2 死键在 JSON 中的表示

```json
{
  "hidUsageID": 0x35,
  "keyName": "grave_accent",
  "label": "`",
  "shiftLabel": "~",
  "deadKey": "grave",
  "row": 1,
  "column": 12
}
```

### 4.3 死键组合规则

死键组合由应用程序层处理，不在 JSON 中定义。建议实现：

```swift
struct DeadKeyCombiner {
    static func combine(deadKey: DeadKey, baseChar: Character) -> Character? {
        switch (deadKey, baseChar) {
        case (.acute, "a"): return "á"
        case (.acute, "e"): return "é"
        case (.acute, "i"): return "í"
        case (.acute, "o"): return "ó"
        case (.acute, "u"): return "ú"
        
        case (.grave, "a"): return "à"
        case (.grave, "e"): return "è"
        
        case (.circumflex, "a"): return "â"
        case (.circumflex, "e"): return "ê"
        case (.circumflex, "i"): return "î"
        case (.circumflex, "o"): return "ô"
        case (.circumflex, "u"): return "û"
        
        case (.diaeresis, "a"): return "ä"
        case (.diaeresis, "e"): return "ë"
        case (.diaeresis, "i"): return "ï"
        case (.diaeresis, "o"): return "ö"
        case (.diaeresis, "u"): return "ü"
        
        case (.tilde, "a"): return "ã"
        case (.tilde, "n"): return "ñ"
        case (.tilde, "o"): return "õ"
        
        case (.ring, "a"): return "å"
        
        case (.cedilla, "c"): return "ç"
        
        default: return nil
        }
    }
}
```

---

## 5. AltGr 键处理

### 5.1 AltGr 的作用

AltGr（Right Alt）用于输入第三层字符，常见于欧洲布局：

- **德语**：AltGr+Q = @, AltGr+E = €, AltGr+ß = \
- **法语**：AltGr+2 = ~, AltGr+3 = #, AltGr+4 = {, AltGr+5 = [, AltGr+0 = }
- **西班牙语**：AltGr+Q = @, AltGr+G = £

### 5.2 AltGr 在 JSON 中的表示

```json
{
  "hidUsageID": 0x14,
  "keyName": "q",
  "label": "q",
  "shiftLabel": "Q",
  "altGrLabel": "@",
  "row": 2,
  "column": 1
}
```

### 5.3 AltGr 修饰键字节

在 USB HID 报告中，AltGr 对应 Right Alt 修饰键位：

```
修饰键字节 (Modifier Byte):
Bit 0: Left Ctrl
Bit 1: Left Shift
Bit 2: Left Alt
Bit 3: Left GUI
Bit 4: Right Ctrl
Bit 5: Right Shift
Bit 6: Right Alt (AltGr)
Bit 7: Right GUI

AltGr 按下时，修饰键字节 = 0x40 (二进制 01000000)
```

---

## 6. 物理标准（Physical Standards）

### 6.1 ANSI（美国标准）

- **特点**：Enter 键为水平矩形
- **布局**：104 键（US 标准）
- **适用**：美国、加拿大、中国、日本等

```
┌─────────────────────────────────────────────┐
│ Enter 键形状：                              │
│ ┌───────┐                                   │
│ │ Enter │  (水平矩形)                        │
│ └───────┘                                   │
└─────────────────────────────────────────────┘
```

### 6.2 ISO（国际标准）

- **特点**：Enter 键为倒 L 形，左 Shift 键较短
- **布局**：105 键（欧洲标准）
- **适用**：欧洲国家（德国、法国、西班牙、意大利等）

```
┌─────────────────────────────────────────────┐
│ Enter 键形状：                              │
│ ┌───────┐                                   │
│ │       │                                   │
│ └───┐   │  (倒 L 形)                        │
│     └───┘                                   │
│                                             │
│ 左 Shift 键较短，多出一个键（| \）           │
└─────────────────────────────────────────────┘
```

### 6.3 JIS（日本标准）

- **特点**：基于 ISO，但有额外的日语特殊键
- **布局**：109 键（日本标准）
- **特殊键**：
  - 無変換 (Muhenkan)
  - 変換 (Henkan)
  - かな (Kana)
  - 半角/全角 (Zenkaku/Hankaku)

```
┌─────────────────────────────────────────────┐
│ 特殊键位置：                                │
│ - 空格键左侧：無変換                        │
│ - 空格键右侧：変換                          │
│ - Backspace 右侧：かな                      │
│ - Esc 下方：半角/全角                        │
└─────────────────────────────────────────────┘
```

---

## 7. 示例布局

### 7.1 US QWERTY 布局（简化版）

```json
{
  "locale": "us",
  "targetOS": "windows",
  "metadata": {
    "name": "US QWERTY",
    "description": "Standard US QWERTY layout",
    "physicalStandard": "ansi",
    "hasAltGr": false
  },
  "keys": [
    {
      "hidUsageID": 0x29,
      "keyName": "Esc",
      "label": "Esc",
      "row": 0,
      "column": 0
    },
    {
      "hidUsageID": 0x35,
      "keyName": "grave_accent",
      "label": "`",
      "shiftLabel": "~",
      "row": 1,
      "column": 0
    },
    {
      "hidUsageID": 0x1E,
      "keyName": "1",
      "label": "1",
      "shiftLabel": "!",
      "row": 1,
      "column": 1
    },
    {
      "hidUsageID": 0x1F,
      "keyName": "2",
      "label": "2",
      "shiftLabel": "@",
      "row": 1,
      "column": 2
    },
    {
      "hidUsageID": 0x14,
      "keyName": "q",
      "label": "Q",
      "shiftLabel": "Q",
      "row": 2,
      "column": 1
    },
    {
      "hidUsageID": 0x04,
      "keyName": "a",
      "label": "A",
      "shiftLabel": "A",
      "row": 3,
      "column": 1
    },
    {
      "hidUsageID": 0x1D,
      "keyName": "z",
      "label": "Z",
      "shiftLabel": "Z",
      "row": 4,
      "column": 1
    },
    {
      "hidUsageID": 0xE1,
      "keyName": "LeftShift",
      "label": "Shift",
      "keyType": "modifier",
      "row": 5,
      "column": 0
    }
  ]
}
```

### 7.2 German QWERTZ 布局（关键差异）

```json
{
  "locale": "de",
  "targetOS": "windows",
  "metadata": {
    "name": "German QWERTZ",
    "description": "German QWERTZ layout with Z/Y swapped and special characters",
    "physicalStandard": "iso",
    "hasAltGr": true
  },
  "keys": [
    {
      "hidUsageID": 0x35,
      "keyName": "circumflex",
      "label": "^",
      "shiftLabel": "°",
      "deadKey": "circumflex",
      "row": 1,
      "column": 0
    },
    {
      "hidUsageID": 0x1F,
      "keyName": "2",
      "label": "2",
      "shiftLabel": "\"",
      "altGrLabel": "²",
      "row": 1,
      "column": 2
    },
    {
      "hidUsageID": 0x1C,
      "keyName": "z",
      "label": "Z",
      "shiftLabel": "Z",
      "row": 2,
      "column": 6
    },
    {
      "hidUsageID": 0x14,
      "keyName": "q",
      "label": "Q",
      "shiftLabel": "Q",
      "altGrLabel": "@",
      "row": 2,
      "column": 1
    },
    {
      "hidUsageID": 0x33,
      "keyName": "semicolon",
      "label": "ö",
      "shiftLabel": "Ö",
      "row": 3,
      "column": 11
    },
    {
      "hidUsageID": 0x34,
      "keyName": "quote",
      "label": "ä",
      "shiftLabel": "Ä",
      "row": 3,
      "column": 12
    },
    {
      "hidUsageID": 0x1D,
      "keyName": "y",
      "label": "Y",
      "shiftLabel": "Y",
      "row": 4,
      "column": 1
    },
    {
      "hidUsageID": 0xE6,
      "keyName": "RightAlt",
      "label": "AltGr",
      "keyType": "modifier",
      "row": 5,
      "column": 5
    }
  ]
}
```

### 7.3 French AZERTY 布局（关键差异）

```json
{
  "locale": "fr",
  "targetOS": "windows",
  "metadata": {
    "name": "French AZERTY",
    "description": "French AZERTY layout",
    "physicalStandard": "iso",
    "hasAltGr": true
  },
  "keys": [
    {
      "hidUsageID": 0x35,
      "keyName": "supra_2",
      "label": "²",
      "row": 1,
      "column": 0
    },
    {
      "hidUsageID": 0x1E,
      "keyName": "1",
      "label": "&",
      "shiftLabel": "1",
      "row": 1,
      "column": 1
    },
    {
      "hidUsageID": 0x1F,
      "keyName": "2",
      "label": "é",
      "shiftLabel": "2",
      "altGrLabel": "~",
      "row": 1,
      "column": 2
    },
    {
      "hidUsageID": 0x14,
      "keyName": "a",
      "label": "A",
      "shiftLabel": "A",
      "row": 2,
      "column": 1
    },
    {
      "hidUsageID": 0x04,
      "keyName": "q",
      "label": "Q",
      "shiftLabel": "Q",
      "row": 2,
      "column": 0
    },
    {
      "hidUsageID": 0xE6,
      "keyName": "RightAlt",
      "label": "AltGr",
      "keyType": "modifier",
      "row": 5,
      "column": 5
    }
  ]
}
```

---

## 8. 验证规则

### 8.1 Schema 验证

使用 JSON Schema Draft-07 进行验证：

```bash
# 安装验证工具
npm install -g ajv-cli

# 验证布局文件
ajv validate -s keyboard-layout-schema.json -d us-qwerty.json
```

### 8.2 业务规则验证

除了 JSON Schema 验证，还需要验证以下业务规则：

1. **HID Usage ID 唯一性**：每个 HID Usage ID 在布局中只能出现一次
2. **物理位置唯一性**：每个 (row, column) 组合只能有一个键
3. **死键一致性**：如果 `deadKey` 字段存在，`label` 必须是该死键的标准符号
4. **AltGr 一致性**：如果 `hasAltGr` 为 false，不应有 `altGrLabel` 字段
5. **修饰键类型**：`keyType` 为 "modifier" 的键，HID Usage ID 必须在 0xE0-0xE7 范围内

### 8.3 验证脚本示例

```python
#!/usr/bin/env python3
import json
import sys

def validate_layout(layout_file):
    with open(layout_file) as f:
        layout = json.load(f)
    
    errors = []
    
    # 检查 HID Usage ID 唯一性
    hid_ids = [k['hidUsageID'] for k in layout['keys']]
    if len(hid_ids) != len(set(hid_ids)):
        errors.append("Duplicate HID Usage IDs found")
    
    # 检查物理位置唯一性
    positions = [(k['row'], k['column']) for k in layout['keys']]
    if len(positions) != len(set(positions)):
        errors.append("Duplicate physical positions found")
    
    # 检查 AltGr 一致性
    if not layout['metadata'].get('hasAltGr', False):
        for key in layout['keys']:
            if 'altGrLabel' in key:
                errors.append(f"Key {key['keyName']} has altGrLabel but hasAltGr is false")
    
    # 检查修饰键类型
    for key in layout['keys']:
        if key.get('keyType') == 'modifier':
            if not (0xE0 <= key['hidUsageID'] <= 0xE7):
                errors.append(f"Modifier key {key['keyName']} has invalid HID Usage ID")
    
    if errors:
        print("Validation failed:")
        for error in errors:
            print(f"  - {error}")
        return False
    
    print("Validation passed")
    return True

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <layout-file>")
        sys.exit(1)
    
    sys.exit(0 if validate_layout(sys.argv[1]) else 1)
```

---

## 9. 与 Swift 代码的映射

### 9.1 JSON 到 Swift 结构的映射

```swift
// 对应的 Swift 结构

struct KeyboardLayoutDefinition: Codable {
    let locale: String
    let targetOS: String
    let metadata: LayoutMetadata
    let keys: [KeyDefinition]
}

struct LayoutMetadata: Codable {
    let name: String
    let description: String?
    let physicalStandard: PhysicalStandard
    let hasAltGr: Bool
    
    enum PhysicalStandard: String, Codable {
        case ansi, iso, jis
    }
}

struct KeyDefinition: Codable {
    let hidUsageID: UInt8
    let keyName: String
    let label: String
    let shiftLabel: String?
    let altGrLabel: String?
    let deadKey: DeadKey?
    let keyType: KeyType
    let width: Double?
    let row: Int
    let column: Int
    
    enum KeyType: String, Codable {
        case regular, modifier, special
    }
    
    enum DeadKey: String, Codable {
        case acute, grave, circumflex, diaeresis, tilde
        case ring, caron, macron, breve, dotAbove
        case cedilla, ogonek, doubleAcute
    }
}
```

### 9.2 加载 JSON 布局

```swift
class KeyboardLayoutLoader {
    func loadLayout(from file: String) throws -> KeyboardLayoutDefinition {
        guard let url = Bundle.main.url(forResource: file, withExtension: "json") else {
            throw LayoutError.fileNotFound
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(KeyboardLayoutDefinition.self, from: data)
    }
    
    enum LayoutError: Error {
        case fileNotFound
        case invalidFormat
    }
}
```

---

## 10. 总结

本 JSON Schema 设计提供了一个完整、灵活、可扩展的键盘布局定义方案：

### 10.1 优势

1. **标准化**：基于 USB HID Usage ID，确保跨平台一致性
2. **完整性**：支持所有字符层（基础、Shift、AltGr）和死键
3. **可读性**：JSON 格式易于阅读和编辑
4. **可验证**：使用 JSON Schema 进行自动验证
5. **可扩展**：易于添加新的布局或修改现有布局

### 10.2 下一步

1. 为所有 14 个支持的布局创建 JSON 文件
2. 实现 JSON 布局加载器
3. 替换现有的硬编码布局构建器
4. 添加布局验证工具
5. 创建布局编辑器（可选）

---

*文档完成于 2026-10-10*
