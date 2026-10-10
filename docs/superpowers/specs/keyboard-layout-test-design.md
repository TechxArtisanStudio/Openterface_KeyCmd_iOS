# 键盘布局全面验证测试设计文档

## 概述

本文档描述 `KeyboardLayoutTests.swift` 的设计，用于验证所有支持的键盘布局（14 个国家/地区 × 3 个操作系统 = 42 种组合）中每个按键的正确性。

---

## 设计目标

### 主要验证内容
1. **布局结构完整性** - 确保每个布局的基本结构符合预期
2. **按键映射正确性** - 验证每个按键的 `keyName`、`label`、`shiftLabel`、`keyCode` 是否正确

### 测试范围
- **地区（Locales）**：14 个
  - US, UK, DE, FR, ES, IT, PT, JP, CN, CA, AU, BE, CH, NORDIC
- **操作系统（TargetOS）**：3 个
  - Windows, macOS, Linux
- **总布局数**：14 × 3 = 42 种组合

---

## 测试用例设计

### 1. 布局结构验证测试

**测试函数名**：`testLayoutStructure()`

**验证内容**：
- 每个布局的行数 ≥ 5（功能行、数字行、3 个字母行、修饰键行）
- 每一行都包含至少一个按键
- 每个按键的 `keyName`、`label`、`keyCode` 都非空
- `keyType` 为有效值（regular、modifier、special、japaneseSpecial）

### 2. 按键映射正确性测试

**测试函数名**：`testKeyMappingCorrectness()`

**验证内容**：
- 对于每个按键：
  - `keyName` 不包含非法字符
  - `label` 是预期的显示字符
  - `keyCode` 符合命名规范（例如数字键应为 `DigitX` 或数字本身）
  - 修饰键的 `shiftLabel` 不为空（如适用）
  - `altGrLabel` 在支持 AltGr 的布局中正确设置

### 3. 特殊地区按键验证测试

**测试函数名**：`testLocaleSpecificKeys()`

**按地区验证特殊按键**：

| 地区 | 特殊按键 | 预期 label | 预期 keyCode |
|------|----------|-----------|--------------|
| JP（日文） | 半角/全角 | 半角/全角 | 半角/全角 |
| JP（日文） | 変換 | 変換 | 変換 |
| JP（日文） | 無変換 | 無変換 | 無変換 |
| JP（日文） | Ro | Ro | Ro |
| DE（德文） | Z 和 Y 位置 | Z 在 T 右，Y 在 Z 右 | - |
| FR（法文） | AltGr 修饰键 | AltGr | AltGr |
| CH（瑞士） | ü, ö, ä 键 | ü, ö, ä | - |
| NORDIC | å, ä, ö 键 | å, ä, ö | - |
| ES（西班牙） | ñ 键 | ñ | - |
| PT（葡萄牙） | ç 键 | ç | - |

### 4. 操作系统特定验证测试

**测试函数名**：`testOSSpecificModifications()`

**验证内容**：
- **Windows**：修饰键标签为 `Ctrl`、`Win`、`Alt`、`Menu`
- **macOS**：修饰键标签为 `⌃`、`⌘`、`⌥`、`fn`
- **Linux**：修饰键标签与 Windows 相同

---

## 测试文件结构

```
KeyCmdTests/
└── KeyboardLayoutTests.swift
    ├── struct KeyboardLayoutTests
    │   ├── @Test func testLayoutStructure()
    │   ├── @Test func testKeyMappingCorrectness()
    │   ├── @Test func testLocaleSpecificKeys()
    │   └── @Test func testOSSpecificModifications()
    └── helper functions:
        ├── func getAllLayoutCombinations() -> [(TargetOS, KeyboardLocale)]
        ├── func validateKeyDefinition(_ key: KeyDefinition, in layout: KeyboardLayoutDefinition)
        └── func assertLocaleSpecificKeys(for locale: KeyboardLocale, layout: KeyboardLayoutDefinition)
```

---

## 测试数据生成

使用 `KeyboardLocale.allCases` 和 `TargetOS.allCases` 动态生成所有 42 种布局组合，避免硬编码。

```swift
private func getAllLayoutCombinations() -> [(TargetOS, KeyboardLocale)] {
    var combinations: [(TargetOS, KeyboardLocale)] = []
    for os in TargetOS.allCases {
        for locale in KeyboardLocale.allCases {
            combinations.append((os, locale))
        }
    }
    return combinations
}
```

---

## 错误处理与失败信息

- 每个断言使用清晰的错误信息，例如：
  - `"Layout \(os.rawValue)_\(locale.rawValue) has no rows"`
  - `"Key \(key.keyName) in \(locale.rawValue) has empty keyCode"`
  - `"Japanese layout missing 半角/全角 key"`

- 使用 `#expect()` 宏（Swift Testing）进行断言，失败时会自动收集所有错误。

---

## 性能考虑

- 使用 `KeyboardLayoutManager.shared.layout(for:os, locale:)` 获取布局，利用缓存避免重复创建
- 测试执行顺序不影响结果（无副作用）
- 预计单个测试运行时间 < 1 秒

---

## 预期输出

测试成功时输出类似：
```
✓ testLayoutStructure passed
✓ testKeyMappingCorrectness passed
✓ testLocaleSpecificKeys passed
✓ testOSSpecificModifications passed
```

测试失败时会明确指出哪个布局、哪个按键有问题。

---

## 后续扩展

如需添加新地区或新 OS，只需更新 `KeyboardLocale` 或 `TargetOS` 枚举，测试会自动覆盖新组合。
