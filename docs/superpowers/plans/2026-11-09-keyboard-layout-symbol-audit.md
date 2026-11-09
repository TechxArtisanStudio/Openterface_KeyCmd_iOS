# 键盘布局符号全量审计与修复计划

> 日期：2026-11-09
> 状态：已完成（待用户目测确认）
> 范围：`Resources/KeyboardLayouts/*.json`（43 个布局文件）；不改固件、不改渲染层代码

## 1. 问题

用户报告法语键盘 UI 按键符号错误，怀疑多个布局都有问题。审计确认：

- 除 `us_macos.json` 外，**所有 macos 变体都是从 PC 模板复制的**：符号是 PC 布局
  （如法语 ²/&/é/"/-/_），不是 Apple 布局（法语应为 </&/é/"/§/!）；修饰键是
  Ctrl/Win/Alt 而非 ⌃/⌥/⌘；字母键位置也有错（法语 M 被放在 bottom row，
  正确应在 home row 的 HID 0x33 处）。
- 审计脚本对 14 个 macos 变体逐键比对 macOS 系统布局（UCKeyTranslate），
  **122 个键的 label/shiftLabel/altGrLabel 与系统真值不符**。
- windows/linux 变体同样有错：法语 M 位置错、ù/! 缺失、ISO 键（HID 0x64）整体缺失；
  德语数字行 shift 层整体错位（3#、6^、7&… 应为 3§、6&、7/…）；
  jp_windows/linux 数字行是美式（2@）而非 JIS（2"）。
- `au_macos` 混入了英式符号（2"、3£、'@），澳大利亚应为美式（2@、3#、'"）。

## 2. 真值来源（可复现）

| 目标 | 真值 | 提取方式 |
|------|------|----------|
| `*_macos.json` | macOS Keyboard Viewer 同源数据 | `scripts/extract_macos_layout_symbols.swift`：TIS 枚举全部 `com.apple.keylayout.*`，UCKeyTranslate 翻译 VK 0–127 的四层（plain/shift/option/shift+option），死键用"死键+空格"解析出键帽符号，并记录每层 dead 标志 |
| `*_windows.json` / `*_linux.json` | PC 标准布局（xkb `basic` 变体，base/shift 层与 Windows 一致） | xkeyboard-config `symbols/{fr,gb,de,es,it,pt,be,ch,se,latin}`（GitLab 镜像），解析键表四层 |

各 locale 的 Apple 参考布局：us/cn→US，uk→British，au→Australian，de→German，
fr→French，es→Spanish-ISO，it→Italian-Pro，pt→Portuguese，ca→Canadian，
be→Belgian，ch→SwissGerman，nordic→Swedish-Pro（瑞典/芬兰 base 层一致）。

HID→VK 映射与比对逻辑：`scripts/audit_layout_symbols.py`。

## 3. 修复方案

写生成器 `scripts/generate_layout_jsons.py`，从真值表**重建**全部布局 JSON
（保留现有文件结构约定），而不是逐文件手改：

1. **结构约定**（与现状一致，渲染层不支持跨行高键，heightMultiplier 未被使用）：
   - row 0：功能行；row 1：数字行；row 2/3/4：字母行；row 5：修饰键行。
   - macos 变体沿用 `us_macos` 模板：小写字母 label、esc/⌫/⇥/⇪/↩/⇧/⌦/≡、
     fn 键（HID 106，本地层）、⌃⌥⌘ 修饰键、row 5 末尾 ←↑↓→。
   - windows/linux 变体沿用现有 PC 模板：Esc/Backspace/Tab/Caps/Enter/Shift 文字、
     Ctrl/Win/Alt（hasAltGr=true 时 RightAlt 标 AltGr）、Menu、row 4 末尾 ↑。
   - **ISO locale（uk/de/fr/es/it/pt/be/ch/nordic）在 row 4 的 LeftShift 后补上
     HID 0x64 键**（法语 @#、德语 ^°、西语 ºª、意语 \| 等）——现有文件全部缺失。
     au/ca 物理上是 ANSI 键盘，保持 ANSI 结构不加 ISO 键。
2. **符号层**：label=plain、shiftLabel=shift（与 plain 相同则省略）、
   altGrLabel=option/AltGr 层（仅 hasAltGr=true 的布局；跳过 U+F8FF 苹果 Logo
   和与 plain/shift 相同的输出）。死键按真值 dead 标志设置 `deadKey` 字段。
3. **keyName**：可打印键直接用 label 字符（全局唯一，生成器断言）；
   带音标字母用描述名（uuml/aring/ugrave…）；功能/修饰键名保持现有约定
   （Esc/Enter/Space/Tab/Backspace/LeftShift/…，校验器与触摸层依赖）。
4. **JIS**：`jp_macos_ansi/jp_macos_jis` 前几日已人工核对（见项目记忆），不动。
   `jp_windows/jp_linux` 只修符号行：数字行改 JIS（2"、7'、-=、^~）、
   ¥ 移到 row 1 末尾（HID 0x89，现在错挂在 HID 0x64）、@`/[{/;+/:*/]} 归位、
   修正 row 4 的 Up 列序错误；row 0/5（変換/無変換/かな/Ro）保持现状。
5. **ca**：保持 Canadian English（≈US）——与 Apple Canadian、Windows Canadian
   English 及现有文件一致；不采用 xkb ca 默认的 CSA 法语变体。

## 4. 验证

- [x] 提取脚本跑通：251 个系统布局（含 dead 标志）
- [x] 审计脚本建立整改前基线：122 个键不符
- [x] 生成器重建 43 个 JSON（jp_macos_* 除外，共 41 个重建 + 2 个保留）
- [x] 审计脚本复跑：macos 变体 0 不符（`audit_layout_symbols.py`）；
      windows/linux 对 xkb 真值 0 不符（新增 `audit_pc_layout_symbols.py`）
- [x] `KeyboardLayoutValidator` 全部通过（loader 加载时自动校验，
      `testLoadAllLayouts` / `testAllLayoutFilesLoadWithoutDuplicatePositions` 覆盖）
- [x] 新增单元测试：加载全部布局 + 关键符号回归（法语 @#、德语 3§、ISO 键存在等）
      → `KeyCmdTests/KeyboardLayoutSymbolTests.swift`（6 个测试）；
      另更新 `KeyboardLayoutTests` 的 fr/be AltGr 断言以接受 macOS 的 RightAlt/⌥
- [x] xcodebuild 构建 + 全部单元测试通过（351 个测试，0 失败，iPhone 17 Pro 模拟器）
- [ ] 真机/模拟器目测法语、德语键盘（用户侧）

## 5. 风险与备注

- 重建会改变 keyName（符号键改用字符本身），已确认 Swift 代码不引用
  locale 特定 keyName；触摸层以 keyName 为键，布局内全局唯一即可。
- `KeyboardTranslationTable`（文本直打功能）从 label 反查按键，符号修正后
  法语/德语文本输入也会随之变正确。
- macOS 变体的 option 层提示（altGrLabel）只覆盖 hasAltGr=true 的布局；
  us/uk/ca/au/cn/jp 维持 hasAltGr=false，不加第四层提示。
- 渲染层对行内键数变化是自适应的（等分宽度），补 ISO 键安全。
- 全量测试暴露的测试自身问题（均已修）：
  旧测试按旧约定用数字 keyName（"1"/"0"）查法语键——
  `RealDeviceHIDTest` 三处（其中两处 `try! XCTUnwrap` 直接崩测试进程）、
  `ModifierIntegrationTest` 两处，改为新的 plain 字符 keyName（&/agrave/…），
  并改用布局 `hidUsageID` 直取（与应用触摸路径一致；keyCode→Keymod 是
  内置 US 布局的兜底路径，不认识新 keyName）。
  `ShiftModifierTest` 隐式假设 US 布局，受共享 locale 污染影响（'a' 解析到
  AZERTY 的 0x14），setUp 显式固定 .us 并在 tearDown 恢复；污染源
  `KeyboardPerformanceTests.testRapidLayoutSwitchingPerformance` 循环设置
  locale 后不复原（setter 会持久化到 UserDefaults），已加 defer 恢复。
- au/ca 的 JSON metadata.physicalStandard=ISO 与 `KeyboardLocale.physicalStandard`
  的 default 分支一致（既有行为），按键本身为 ANSI 结构无 ISO 键；改枚举超出
  本次符号审计范围，未动。