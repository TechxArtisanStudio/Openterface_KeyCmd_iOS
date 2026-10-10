# Task 2.0 Report: 设计 JSON 布局架构

> 日期：2026-10-10  
> 状态：Complete  
> Commit: c64490a

---

## 1. 任务概述

设计 JSON schema，参考 VirtualBox 的 devhid.cpp 方法，为每个 HID Usage ID 定义完整的字符映射。

## 2. 交付物

### 2.1 创建的文件

- `docs/superpowers/specs/keyboard-layout-json-schema.md` (678 行)

### 2.2 文档内容

文档包含以下章节：

1. **设计目标** - 核心问题和设计原则
2. **JSON Schema 设计** - 顶层结构、Metadata、KeyDefinition 定义
3. **与 VirtualBox devhid.cpp 的对应关系** - 对比分析
4. **HID Usage ID 映射规则** - 字母键、数字键、控制键、修饰键、特殊符号键
5. **死键（Dead Key）处理** - 概念、定义、组合规则
6. **AltGr 组合处理** - 概念、定义、优先级规则
7. **完整布局示例** - US 布局和德语布局示例
8. **实现指南** - 加载、转换、使用翻译表
9. **验证规则** - Schema 验证和业务规则验证
10. **未来扩展** - 可能的扩展方向
11. **参考资源** - USB HID、VirtualBox、JSON Schema 规范

## 3. 设计亮点

### 3.1 借鉴 VirtualBox 的设计

- 使用 USB HID Usage ID 作为统一的键码表示
- 静态映射表思想（但使用 JSON 而非 C++ 数组）
- 物理位置与逻辑键码分离

### 3.2 改进之处

| 方面 | VirtualBox | KeyCmd JSON Schema |
|------|-----------|-------------------|
| 数据格式 | C++ 静态数组 | JSON 文件 |
| 映射目标 | Linux keycode | 字符标签 + HID Usage ID |
| 布局支持 | 单一映射表 | 每个布局独立定义 |
| 修饰键处理 | 基础支持 | 完整的 Shift/AltGr/Dead key |
| 可扩展性 | 需要重新编译 | 动态加载 JSON |

### 3.3 完整的字符映射

为每个 HID Usage ID 定义了：
- `label`：基础字符
- `shiftLabel`：Shift 组合字符
- `altGrLabel`：AltGr 组合字符
- `deadKey`：死键类型（可选）

### 3.4 死键和 AltGr 支持

- 定义了 12 种死键类型
- 明确了 AltGr 优先级规则
- 提供了组合逻辑的实现指南

## 4. 自审结果

### 4.1 完整性检查

- [x] JSON Schema 定义完整
- [x] 所有 HID Usage ID 类别都有示例
- [x] 死键和 AltGr 处理规则清晰
- [x] 包含完整的布局示例
- [x] 提供实现指南

### 4.2 一致性检查

- [x] 与现有 Swift 结构（KeyDefinition, KeyboardLayoutDefinition）对齐
- [x] 与 Phase 1 实现的 HIDUsageID 枚举一致
- [x] 与 VirtualBox 架构文档的对应关系明确

### 4.3 可用性检查

- [x] 文档结构清晰，易于理解
- [x] 示例代码可直接用于实现
- [x] 验证规则明确

## 5. 下一步

Task 2.0 是设计任务，为后续实现任务奠定基础：

- **Task 2.1**: 创建 US 布局 JSON 文件
- **Task 2.2**: 创建德语布局 JSON 文件
- **Task 2.3**: 创建法语布局 JSON 文件
- **Task 2.4**: 实现 JSON 布局加载器

## 6. 结论

Task 2.0 成功完成了 JSON 布局架构设计，为 Phase 2 的实现任务提供了清晰的设计规范。文档详细说明了：

1. JSON Schema 的完整定义
2. 与 VirtualBox 设计的对应关系
3. HID Usage ID 映射规则
4. 死键和 AltGr 处理机制
5. 实现指南和验证规则

设计遵循了数据驱动、标准化、完整性和可扩展性的原则，为构建灵活、可维护的键盘布局系统奠定了基础。

---

*报告完成于 2026-10-10*
