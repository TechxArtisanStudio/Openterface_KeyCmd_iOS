# BLE 配对码（PIN）与绑定管理（iOS 端）

日期：2026-11-10
状态：已实现（2026-11-10），真机矩阵待验证
固件基线：`Openterface_KM` @ `62626eb`（`docs/ble-pairing-design.md` 的 M1 + M2 已实现）
目标产品：KeyMod（`BOARD_VERSION=3`），KVM-GO 等 `ENABLE_BLE` 机型通用

## 1. 目标

固件现在把 BLE 数据通路压在"已配对 + 已加密"之下：未配对的手机连 FFF1 订阅、写 FFF2 都会被拒绝。
设备出厂配对码统一为 **666666**，可在已加密链路上改为私有 6 位数字；默认只保留 **1 个绑定槽**。

iOS App 需要：

1. 让首次连接能够正常触发 iOS 系统配对弹窗，并在配对失败时给出可操作的提示；
2. 把"连接成功"的判定从 `didConnect` 改为"FFF1 订阅成功"（即链路已加密），否则 HID 写入会静默失败；
3. 新增"配对与安全"入口：查看绑定槽状态、改配对码、解除绑定（恢复出厂安全参数）；
4. 处理设备解绑后重启、iOS 侧残留旧绑定、自动重连死循环等边界；
5. 不破坏改名、ECM 网络、BLE-Eth SSH 隧道等既有功能。

> 范围外：设置绑定槽上限（固件只允许 USB 下发 `0x22 0x05`，BLE 会返回 `0xE5`）；
> Android 端同步改造；固件 M3 的按键长按重置。

## 2. 固件变更事实（已对照源码）

### 2.1 数据通路准入

| 项 | 变更 | 源码 |
|---|---|---|
| FFF2 值属性 | `GATT_PERMIT_WRITE` → `GATT_PERMIT_WRITE \| GATT_PERMIT_ENCRYPT_WRITE` | [ble_usb_service.c:138](file:///Users/txa/project/Openterface_KM/Profile/ble_usb_service.c#L138) |
| FFF1 CCCD | 追加 `GATT_PERMIT_ENCRYPT_WRITE` | [ble_usb_service.c:124](file:///Users/txa/project/Openterface_KM/Profile/ble_usb_service.c#L124) |
| 应用层兜底 | `ble_usb_ServiceEvt` 收到数据先查 `linkDB_State(LINK_ENCRYPTED)` | [peripheral.c:1186](file:///Users/txa/project/Openterface_KM/APP/peripheral.c#L1186) |

结论：**FFF1 订阅成功 = 链路已加密**（iOS 在写 CCCD 时才会发起配对）。这是 App 唯一可靠的"可以发数据"信号。

### 2.2 配对与 PIN

- 默认配对码 `666666`（`BLE_PAIR_DEFAULT_PIN`），见 [ble_pair_config.h:17](file:///Users/txa/project/Openterface_KM/APP/include/ble_pair_config.h#L17)。
- 启动时把有效 PIN 交给 Bond Manager，`MITM=TRUE`、`IO_CAP_DISPLAY_ONLY`、bonding 开启，见 [peripheral.c:544](file:///Users/txa/project/Openterface_KM/APP/peripheral.c#L544)。
- 设备无屏无键，**PIN 只从手机侧输入，固件永不通过 BLE 回传 PIN**（没有"读取当前 PIN"的命令）。
- 改 PIN 后只影响**下一次配对**；已存绑定不受影响。
- 配对成功/失败由 `Peripheral_PairStateCB` 驱动 LED 态 5/6，见 [peripheral.c:428](file:///Users/txa/project/Openterface_KM/APP/peripheral.c#L428)。

### 2.3 绑定槽与准入

- 默认上限 **1** 台手机；可配 1..4，但只接受 USB 下发。
- 判定式：`bondCount >= maxBonds` → `GAPBOND_PAIRING_MODE_NO_PAIRING`，否则 `WAIT_FOR_REQ`，见 [peripheral.c:408](file:///Users/txa/project/Openterface_KM/APP/peripheral.c#L408)。
- `GAPBOND_ERASE_AUTO=0` 显式关闭，避免第 N+1 台配对时静默清空旧绑定，见 [peripheral.c:560](file:///Users/txa/project/Openterface_KM/APP/peripheral.c#L560)。
- 已绑定的手机重连走存储的 LTK，不受 `NO_PAIRING` 影响。

### 2.4 `0x22` 安全命令集（以源码为准）

分发在 [usbd_compostie_km.c:303](file:///Users/txa/project/Openterface_KM/APP/usbd_compostie_km.c#L303)，实现在
[peripheral.c:1389](file:///Users/txa/project/Openterface_KM/APP/peripheral.c#L1389)。

| 子命令 | 语义 | 请求 payload | 成功响应 payload | 链路要求 |
|---|---|---|---|---|
| `0x01` | 配对窗口（已废弃） | `[01]` | 无，返回 `0xE5` | — |
| `0x02` | 擦除全部绑定 + 清 PIN override + 槽位回 1，然后重启 | `[02]` | `[status]` | USB 或已加密 BLE |
| `0x03` | 绑定状态 | `[03]` | `[status, count, max_bonds]` | USB 或已加密 BLE |
| `0x04` | 设置 PIN override | `[04] + 6 字节 ASCII 数字` | `[status]` | USB 或已加密 BLE，不回显 |
| `0x05` | 设置槽位上限 | `[05, 1..4]` | `[status]` | **仅 USB**；BLE 下发返回 `0xE5` |
| `0x06` | 读槽位上限 | `[06]` | `[status, max_bonds]` | USB 或已加密 BLE |

响应命令字节：成功 `cmd | 0x80` = **0xA2**，失败 `cmd | 0xC0` = **0xE2**，见 [usbd_compostie_km.c:94](file:///Users/txa/project/Openterface_KM/APP/usbd_compostie_km.c#L94)。

状态码：`0x00` 成功、`0xE5` 参数错误。本命令集 Flash 写入失败统一返回 `0xEA`
（[peripheral.c:1444](file:///Users/txa/project/Openterface_KM/APP/peripheral.c#L1444)）；
`0xE9/0xEB` 不会由这组 handler 产生，UI 只需按通用错误展示。

### 2.5 帧路由与消歧

固件先判断 BLE-Eth ECM 帧再判断 CH9329，见 [peripheral.c:215](file:///Users/txa/project/Openterface_KM/APP/peripheral.c#L215)。
`0x22` 的判据：

- `payload len == 1 && byte == 0x04` → ECM"恢复默认"（BLE-Eth）；
- `payload len == 9/13/21` → ECM SET；
- 其余 `0x22` 帧 → CH9329 安全命令。

因此本功能的帧形状都安全：

| 命令 | 帧（addr=0x00） | 说明 |
|---|---|---|
| 擦除绑定 | `57 AB 00 22 01 02 27` | len=1，byte≠0x04 |
| 绑定状态 | `57 AB 00 22 01 03 28` | len=1 |
| 设置 PIN `123456` | `57 AB 00 22 07 04 31 32 33 34 35 36 64` | len=7，不匹配 ECM 的 1/9/13/21 |
| 读槽位上限 | `57 AB 00 22 01 06 2B` | len=1 |

> 响应 `0xA2` 与 ECM SET 成功响应**同字节**。其中 `0x02/0x04` 的成功响应
> （`[status]`，无后续数据）与 ECM SET 完全无法区分；`0x03/0x06` 虽可靠长度区分，
> 但不应依赖。统一靠 BLEManager 的"同一时刻只有一个控制窗口"来保证。

### 2.6 `0x02` 的行为陷阱

`0x02` 不是单纯"解绑"，而是**恢复出厂安全参数**：

1. 擦除全部 bond；
2. 清 PIN override（**配对码回到 666666**）；
3. 绑定上限回到 1；
4. 500 ms 后设备重启（[peripheral.c:1417](file:///Users/txa/project/Openterface_KM/APP/peripheral.c#L1417)）。

所以"先改 PIN 再解绑移交"是无效的：解绑会把 PIN 一起清掉。正确顺序是
**旧手机解绑 → 旧手机在系统设置里忽略设备 → 新手机用 666666 配对 → 新手机再改 PIN**。
UI 必须在解绑确认框里写明这一点。

## 3. 对 iOS 端的直接影响

### 3.1 连接就绪判定必须改

当前 [BLEManager.swift:338](file:///Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/BLEManager.swift#L338) 在 `didConnect` 就置 `.connected` 并持久化设备；
[BLEManager.swift:406](file:///Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/BLEManager.swift#L406) 在发现特征后立刻 `setNotifyValue(true)`。

新固件下：

- `didConnect` 只代表链路建立，**不代表已加密**；
- `setNotifyValue(true)` 写 CCCD 时由 iOS 触发系统配对弹窗；
- 订阅成功回调 `didUpdateNotificationStateFor(isNotifying: true)` 才是"链路已加密、可以发数据"；
- FFF2 的 HID 写入是 `.withoutResponse`，未加密时**不会报错，只会静默丢弃**——绝不能用"连上了"当"能操控"。

改造：把 `didConnect` 末尾的收尾工作抽成 `finalizeConnection()`，由 FFF1 订阅成功回调调用。
`connectionState` 在配对期间保持 `.connecting`，新增 `isWaitingForPairing` 驱动文案，避免给枚举加新 case
（`ContentView.swift:663` 等处有穷举 switch）。

### 3.2 iOS 的能力边界（决定 UX 写法）

| 能力 | iOS 是否支持 | 结论 |
|---|---|---|
| App 代为输入配对码 | 否 | 只能由 iOS 系统弹窗输入；App 里的 PIN 输入框**只用于改 PIN**，不是配对输入 |
| 主动发起配对 | 否 | 只能通过访问受保护属性（订阅 FFF1 / 写 FFF2）触发 |
| 查询是否已绑定 | 否 | 只能靠"订阅是否成功"推断链路已加密 |
| 读取链路加密状态 | 否 | 同上 |
| 删除 iOS 侧旧绑定 | 否 | 只能引导用户到 设置 > 蓝牙 > 忽略此设备 |
| 深链到蓝牙设置 | 否（公开 API） | 只能给文字步骤，可提供"复制设备名" |

触发时机：App 调 `setNotifyValue` 后弹窗；用户取消或输错 PIN 时，订阅回调带错误或连接断开。
错误映射（实现时以实测为准）：

- `CBATTError.insufficientEncryption`（0x0F）：属性访问被拒，配对未完成；
- `CBError.peerRemovedPairingInformation`（14）：设备侧已删除绑定，iOS 还留着旧记录；
- `CBError.encryptionTimedOut`（15）：加密握手超时。

### 3.3 升级迁移与旧固件

- 固件从旧版升级后，ROM 里的旧 bond **可能保留**（取决于烧录是否整片擦除，需实测）。
  若旧手机还绑着，新固件下它仍可加密重连，且占满唯一的槽位 → 新手机无法配对。
- 若设备槽位被别的手机占用，**iOS App 无法自救**（所有 `0x22` 命令都要求已加密链路），
  只能让用户用电脑 + USB 串口工具下发 `0x22 0x02`。提示文案必须写清楚。
- 旧固件不认识 `0x04/0x06`：`0x03` 会返回假数据 `[00, 00, 00]`（max=0）。App 以
  `max_bonds == 0` 判定"固件不支持配对管理"，安全页显示只读说明，不展示改 PIN / 解绑表单。
- 旧版 App + 新固件：旧 App 也会在订阅 FFF1 时弹系统 PIN 框。输对可用，取消则 HID 静默失效。
  这是固件 M1 的预期断层，需与新 App 同批发版。

## 4. UX 设计

### 4.1 首次配对

1. 用户在扫描页点设备 → 连接；
2. 连接对话框状态显示"正在配对…"；
3. iOS 弹出系统"蓝牙配对请求"，用户输入 6 位配对码（出厂 `666666`）；
4. 订阅成功 → 进入已连接；失败 → 显示配对失败卡片。

扫描页底部加一行常驻说明："首次配对请使用设备配对码，出厂为 666666。"（不弹模态框，避免打断）。
不在 App 内做"配对码输入页"——那会和改 PIN 的输入框混淆。

### 4.2 配对失败 / 设备已被占用

失败卡片文案必须覆盖三种可能，因为 App 无法区分：

- 配对码输错或取消了系统弹窗；
- 设备已被另一台手机占用（单槽满员，固件直接 `NO_PAIRING`，iOS 可能根本不弹框）；
- iOS 侧残留旧绑定，设备侧已删除。

卡片提供：

- "重试连接"；
- "如何解决"（展开文字步骤）：
  1. 确认配对码（出厂 666666）；
  2. 若设备之前配过别的手机，请先用 USB 串口工具执行 `0x22 0x02`；
  3. 若本机以前连过该设备，到 设置 > 蓝牙 > 设备名 > 忽略此设备，再重连；
  4. 仍不行时，关闭再打开 iPhone 蓝牙后重试。
- "复制设备名"，方便在系统设置里找到它。

### 4.3 首次配对成功后的 PIN 提醒

固件没有"是否改过 PIN"的读取命令，App 只能做**一次性启发式提醒**：

- 首次成功连接该设备（本机 `UserDefaults` 无记录）→ 在连接对话框显示横幅：
  "该设备可能仍在使用出厂配对码 666666。建议改为私有配对码。"
- 横幅按钮 → 打开"配对与安全"；可"忽略"。
- 在 App 内改 PIN 成功后记录 `pin_changed_<uuid>`，不再提醒；解绑成功后清除该记录。
- 文案用"可能"，因为无法确认设备当前 PIN 是否被别处改过。

### 4.4 换机 / 解绑

入口："配对与安全" → "重置配对（恢复出厂安全参数）"，红色按钮 + 二次确认。
确认框必须写明：

> 将删除设备上的全部配对记录，配对码恢复为 666666，仅保留 1 个绑定槽，随后设备重启。
> 这台 iPhone 还需要在 设置 > 蓝牙 中"忽略此设备"，才能重新配对或交给新手机。

发送 `0x22 0x02` 成功（收到 `0xA2`）后：

1. 立即显示"已重置，等待设备重启"；
2. 设置 `suppressAutoReconnect`，取消自动重连；
3. 清除保存的 `lastConnectedUUID/Name`（保留 known UUID，设备仍可被扫描到）；
4. 设备断开后保持断开，显示后续步骤（旧手机忽略设备 → 新手机用 666666 配对 → 新手机改 PIN）；
5. 用户关闭面板后恢复正常扫描/手动连接。

### 4.5 明确不做

- 不做 App 内配对码输入（系统弹窗才是配对入口）；
- 不做绑定槽上限编辑（BLE 下发必被拒，只读显示）；
- 不做"读取当前 PIN"（固件不提供）；
- 不自动清除 iOS 系统绑定（无公开 API）；
- 不把配对码存进 `UserDefaults` 或日志；改 PIN 的输入框用后即清。
- 不做后台定时查询绑定状态（无必要，且每次查询都要占用控制窗口）。

## 5. 命令层：`KeyCmd/Services/BLESecurityCommand.swift`（新增）

纯逻辑 enum，复用 `BLENameCommand.frame(cmd:payload:)`：

```swift
enum BLESecurityCommand {
    static let cmd: UInt8 = 0x22
    static let responseCommands: Set<UInt8> = [0xA2, 0xE2]

    struct Status: Equatable { let bondCount: UInt8; let maxBonds: UInt8 }

    static func statusFrame() -> Data                    // [03]
    static func readMaxBondsFrame() -> Data              // [06]
    static func setPINFrame(_ pin: String) -> Data?      // 6 位 ASCII 数字
    static func eraseBondsFrame() -> Data                // [02]

    static func validatePIN(_ pin: String) -> Bool       // 恰好 6 位 0-9
    static func parseStatus(_ payload: Data) -> Status?  // 2 字节：[count, max]
    static func parseMaxBonds(_ payload: Data) -> UInt8? // 1 字节：[max]
}
```

要点：

- PIN 允许前导零（固件按 `uint32` 解析，`000123` 等价于 `123`，与 iOS 系统输入的数值一致）；
- `parseStatus` 必须严格校验 `payload.count == 2`；否则 `.invalidResponse`；
- 不实现 `0x05`（BLE 必拒），在文档和 UI 里说明只能 USB 配置；
- 所有状态码原样透出，UI 再解释。

已知帧向量（单测逐字节断言）：

| 操作 | 帧 |
|---|---|
| 擦除绑定 | `57 AB 00 22 01 02 27` |
| 绑定状态 | `57 AB 00 22 01 03 28` |
| 读上限 | `57 AB 00 22 01 06 2B` |
| 设置 PIN 123456 | `57 AB 00 22 07 04 31 32 33 34 35 36 64` |

响应示例：

| 响应 | 字节 | 解析 |
|---|---|---|
| 状态 count=1 max=1 | `57 AB 00 A2 03 00 01 01 A9` | status=0, payload=[1,1] |
| 上限=1 | `57 AB 00 A2 02 00 01 A7` | payload=[1] |
| 擦除成功 | `57 AB 00 A2 01 00 A5` | payload=[] |
| 参数错误 | `57 AB 00 E2 01 E5 CA` | status=0xE5 |

## 6. BLEManager 接入

### 6.1 连接状态机

新增私有/发布状态：

```swift
@Published private(set) var isWaitingForPairing: Bool = false
@Published private(set) var pairingIssue: PairingIssue?
@Published private(set) var securityState: SecurityState = .idle

enum PairingIssue: Equatable {
    case authenticationFailed   // 输错/取消/被占用，无法区分
    case staleBond              // 设备删了绑定、iOS 还留着
    case timeout
}
```

流程：

1. `didConnect`：停扫描、记录 peripheral、发现服务、启动 RSSI；**不再置 `.connected`、不持久化**；
2. `didDiscoverCharacteristicsFor`：保存 FFF1/FFF2；设置 `.connecting` + `isWaitingForPairing = true`；
   启动 120 s 配对超时（可覆盖用户慢慢输入 PIN；超时 → `pairingIssue = .timeout` 并主动
   `cancelPeripheralConnection`，避免系统弹窗卡死）；调用 `setNotifyValue(true)`；
3. `didUpdateNotificationStateFor(isNotifying: true)`：取消配对超时 → `finalizeConnection()`
   （置 `.connected`、插入 `connectedDevices`、持久化 UUID/Name、完成改名成功、清 `pairingIssue`、
   首次连接提醒判断）；
4. 订阅回调 error / `isNotifying == false`：按 3.2 映射 `pairingIssue`，断开并停在 `.disconnected`；
5. `didDisconnect`：
   - 有改名/ECM/安全操作在途 → 走既有失败路径；
   - `isWaitingForPairing` → `pairingIssue = .authenticationFailed`，**不自动重连**；
   - 错误码 14/15 → `pairingIssue = .staleBond`，**不自动重连**；
   - `suppressAutoReconnect` → 不自动重连；
   - 其余保持现有自动重连逻辑。

> 自动重连失败 3 次会在配对场景里表现为"设备一直闪断"，必须在第一次配对相关失败时就停。

### 6.2 安全命令流程

仿 ECM 流程（bleQueue 串行 + scanner + 5 s 超时 + flush）：

- 私有：`securityScanner`、`securityResponseTimeout`、`suppressAutoReconnect`；
- `fetchSecurityStatus()`：guard 已连接 + fff2 + **无改名/ECM/安全在途** → 发 `0x03`；
- `setPairingPIN(_:)`：先 `validatePIN`，再发 `0x04`（**禁止 hex 日志**）；
- `erasePairing()`：发 `0x02`；成功即进入 `.erased`，设置 `suppressAutoReconnect`；
- `dismissSecurityResult()`：failure → idle；
- 响应路由：rename → ECM → security → 原始数据透传；
- **互斥**：`beginRename` / `beginECMRequest` / `beginSecurityRequest` 三处互相 guard；
  `securityScanner != nil` 时另两者返回 `.busy`。`0xA2` 与 ECM SET 共字节，互斥是硬要求；
- 断连：`securityScanner` flush；若有在途操作 → `.failure(.disconnected)`。

状态：

```swift
enum SecurityState: Equatable {
    case idle
    case loading
    case ready(BLESecurityCommand.Status)
    case savingPIN          // 改 PIN 中
    case pinSaved
    case erasing
    case erased
    case unsupportedFirmware
    case failure(SecurityFailure)
}
enum SecurityFailure: Equatable {
    case notConnected, busy, noResponse, rejected(UInt8), invalidResponse, disconnected
}
```

### 6.3 其他细节

- 增加 `peripheral(_:didWriteValueFor:error:)`：控制帧用 `.withResponse`，未加密时会带
  `CBATTError.insufficientEncryption`，用于补充配对失败判定（HID 的 `.withoutResponse` 没有回调）。
- `sendRawData` 已不打印 hex；改 PIN 路径额外保证不把 payload 写进 `LogManager`。
- `connectToDevice` 时清 `pairingIssue`、`securityState`、`suppressAutoReconnect`；
  扫描页手动连接是恢复入口。
- 改 PIN 成功不清除 `lastConnectedUUID`，不断链。
- 擦除成功后**不要**立即 `cancelPeripheralConnection`：让固件自然重启断开；若 3 s 内没断再主动断开。

## 7. UI

### 7.1 `KeyCmd/View/Connection/BLESecuritySheet.swift`（新增）

仿 `ECMIPSheet`：`NavigationView` + `ScrollView`（矮窗口可滚动），`interactiveDismissDisabled` 仅在操作中。

内容：

- 状态区：`已配对手机 1 / 1`；`槽位已满，新手机无法配对`；说明"默认只允许 1 台手机，更多槽位需用 USB 配置"。
- 改配对码：
  - 两个输入框（新配对码 / 确认配对码），6 位数字键盘，等宽字体；
  - 本地校验：恰好 6 位、两次一致、纯 ASCII 数字；
  - 说明："只影响下一次配对；当前已配对的手机会保持连接。"
  - 成功 → 清空输入 → "配对码已更新"。
- 重置配对（红色）：
  - 二次确认，文案见 §4.4；
  - `erasing` 时禁用关闭；`erased` 后显示三步交接说明和"完成"。
- 固件不支持：只显示"该设备固件不支持配对管理" + 升级提示，隐藏读写表单。
- 失败原因映射（`notConnected / busy / noResponse / rejected(0x..) / invalidResponse / disconnected`）。

### 7.2 `ConnectionDialogView.swift`

- 在"ECM 网络"下方加"配对与安全"行（lock 图标），仅 `.connected` 时显示；
- 顶部状态文案：`isWaitingForPairing` 时显示"正在配对…请在 iOS 弹窗中输入配对码（出厂 666666）"；
- `pairingIssue != nil` 时显示橙色告警卡（§4.2）；
- 首次配对提醒横幅（§4.3），可跳转安全页；
- 新增 `showSecurity` sheet。

### 7.3 `BluetoothScannerView.swift`

- 列表底部加常驻说明："首次配对请使用设备配对码，出厂为 666666。"
- 不改连接动作，避免多一步确认。

### 7.4 `ContentView.swift`

- 若状态文案/图标有穷举 switch，补上"配对中"的显示（沿用 `.connecting`，不改枚举）。

## 8. 本地化（6 语言）

`en / zh-Hans / zh-Hant / ja / ko / fr` 的 `Localizable.strings` 追加，键名用英文原文（与现有风格一致）：

- 入口与标题：`Pairing & Security`、`Pairing PIN`、`Change Pairing PIN`
- 状态：`Paired phones: %d of %d`、`Pairing slot is full`、`Only one phone is paired by default...`
- 配对中/失败：`Waiting for pairing...`、`Enter the 6-digit PIN in the iOS prompt (factory default 666666).`
  `Pairing failed`、`How to fix`、`The device may already be paired with another phone.`
  `Go to Settings > Bluetooth, tap the device, and choose "Forget This Device".`
- PIN 表单：`New pairing PIN`、`Confirm pairing PIN`、`PIN must be exactly 6 digits.`、`PINs do not match.`
  `The PIN is used the next time a phone pairs. The current pairing stays connected.`
  `Pairing PIN updated.`
- 重置：`Reset Pairing`、`This erases all pairing records, restores the PIN to 666666, keeps one pairing slot, and restarts the device.`
  `This iPhone must also forget the device in Settings > Bluetooth.`、`Pairing reset. Waiting for the device to restart...`
- 不支持：`This device firmware does not support pairing management.`、`Connect over USB to reset pairing.`
- 提醒横幅：`This device may still use the factory PIN 666666. Change it to keep others out.`

## 9. 测试

### 9.1 单元测试：`KeyCmdTests/BLESecurityCommandTests.swift`（新增）

- 四个命令帧逐字节断言（含 checksum，向量见 §5）；
- `validatePIN`：长度 5/6/7、非数字、空格、全角数字、前导零；
- `parseStatus` / `parseMaxBonds`：正确长度、空/多字节返回 nil；
- 错误响应：`0xE2` + `0xE5/0xE9/0xEA/0xEB` 的 status 提取；
- 扫描器（`targetCommands: [0xA2, 0xE2]`）：
  - `0xA2` 状态响应分片到达；
  - 隧道帧透传；
  - 坏校验和透传；
  - `0xE2` 错误响应识别；
- 响应与 ECM `0xA2` 同字节的事实用注释说明，互斥由 BLEManager 保证（不引入跨层单测）。

### 9.2 真机矩阵（KeyMod）

| # | 用例 | 预期 |
|---|---|---|
| P1 | 空绑定设备连接 | iOS 系统弹 PIN 框；输入 666666 后订阅成功、可操控 |
| P2 | 输错 PIN | 设备 LED 6；App 显示配对失败卡；重试可再次弹框 |
| P3 | 取消系统弹框 | 连接断开或订阅失败；App 显示失败卡；无自动重连风暴 |
| P4 | 配对成功后杀 App 重启 | 不再弹框，直接加密重连，安全页可查询 count=1 max=1 |
| P5 | 设备已被另一台手机占用（单槽） | 不弹框或订阅失败；App 提示"可能已被占用/用 USB 重置" |
| P6 | App 内重置配对 | 收到 `0xA2`；设备重启；App 不自动重连；旧 iPhone 忽略设备后新手机可用 666666 配对 |
| P7 | 改 PIN 为 123456 | 成功；当前连接不断；解绑后 PIN 回 666666（确认陷阱文案） |
| P8 | 改 PIN 前导零 000123 | 设备接受；下次配对输入 000123 成功 |
| P9 | 设备被 USB 执行 `0x22 0x02` 后本机重连 | 报 `peerRemovedPairingInformation` 或加密失败；App 引导"忽略此设备"；不循环重连 |
| P10 | 旧固件 | 不弹框、功能照旧；安全页显示"不支持"；无回归 |
| P11 | 改名 / ECM IP / 安全命令连续操作 | 三者互斥，无 `0xA2` 串扰，隧道不受影响 |
| P12 | 加密链路下 SSH 隧道 | 连接与吞吐正常 |
| P13 | 重启后 PIN 保持 | 固件 T16/重启保持 |
| P14 | 固件升级后旧 bond 是否保留 | 记录实际行为，决定升级引导文案 |

### 9.3 构建与测试命令

```bash
xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  > /tmp/keycmd_pairing.log 2>&1
```

## 10. 文件清单

新增：

- [x] `KeyCmd/Services/BLESecurityCommand.swift`
- [x] `KeyCmd/View/Connection/BLESecuritySheet.swift`
- [x] `KeyCmdTests/BLESecurityCommandTests.swift`

修改：

- [x] `KeyCmd/Managers/BLEManager.swift`（连接就绪判定、配对失败状态、安全命令、互斥、写回调）
- [x] `KeyCmd/View/Connection/ConnectionDialogView.swift`（入口、状态、告警卡、提醒横幅）
- [x] `KeyCmd/View/Connection/BluetoothScannerView.swift`（默认 PIN 说明）
- [x] `KeyCmd/View/ContentView.swift`（无需修改：未新增 `ConnectionState` 枚举值）
- [x] `KeyCmd/Resources/Localizations/*.lproj/Localizable.strings` × 6
- [x] ~~`KeyCmd.xcodeproj/project.pbxproj`~~ 无需修改：项目使用 Xcode 16
  `PBXFileSystemSynchronizedRootGroup`，新文件自动纳入

## 11. 实施顺序

### 第 0 步：真机行为验证（写代码前）

用当前 App + 新固件做一次手动 spike，记录：

1. `setNotifyValue` 是否稳定弹出 iOS PIN 框；
2. 输错 / 取消 / 超时分别走哪个回调、错误码是什么、连接是否断开；
3. 设备被占用时 iOS 是否弹框；
4. 设备侧删绑定后 iOS 重连的错误码与恢复路径（是否必须"忽略此设备"）；
5. 固件升级后旧 bond 是否保留。

这一步决定 §3.2 的错误映射和 §4.2 的文案，避免 UI 做完才发现系统行为不同。

### M1 — 命令层（已完成）

`BLESecurityCommand` + 单测。可完全离线完成。

### M2 — 连接门禁（承重，已完成）

连接状态机改造 + 配对失败状态 + 自动重连抑制。没有这一步，新固件下 App 会"显示已连接但 HID 无效"。

### M3 — 安全页（已完成）

状态查询、改 PIN、重置配对、交接指引、首次提醒。

### M4 — 收尾（代码完成，真机待验证）

6 语言本地化、真机矩阵、更新本计划勾选状态。

## 12. 风险与待验证

| 风险 | 处置 |
|---|---|
| iOS 系统弹窗行为未实测（固件 P3） | 第 0 步 spike；M2 前必须完成 |
| 无法区分"PIN 错"与"设备被占用" | 用一条覆盖两种可能的文案，不做假精确提示 |
| 设备删绑定后 iOS 保留旧记录 | 无公开 API；先取消/重连一次，仍失败则引导"忽略此设备" |
| 无蓝牙设置深链 | 给路径 + "复制设备名"，不承诺跳转 |
| 旧 bond 跨固件升级是否保留不确定 | P14 实测；文案按"可能已占用"写 |
| 解绑会同时清 PIN override | 确认框和交接步骤明确写出；不提供"改 PIN 后移交"的误导路径 |
| 三套命令窗口共享 `0xA2` | 严格互斥；安全页打开前若 ECM/改名在途则返回 busy |
| 配对重连风暴 | 配对相关失败立即停止自动重连，置 `pairingIssue` |
| PIN 泄漏 | 不落盘、不打 hex 日志、输入框用后清空；测试用假 PIN |
| 旧 App + 新固件断层 | 与固件同批发版；新 App 提供失败解释 |

## 13. 验证清单

- [ ] 第 0 步真机 spike 完成，错误码与系统行为已记录
- [x] `BLESecurityCommandTests` 全部通过
- [x] 全量 `xcodebuild test` 通过（392 tests, 0 failures）
- [ ] P1–P14 真机矩阵通过（P14 至少记录现象）
- [x] 配对中 HID 不再"假连接"：未订阅成功前无法发送、UI 明确显示配对中
- [x] 改名 / ECM / 安全命令互斥无串扰
- [x] 解绑后不自动重连、不反复扫描重连
- [x] 6 语言文案齐全，无硬编码英文
- [x] 日志中不出现配对码
- [x] 本计划状态与勾选更新

## 14. 实施记录（2026-11-10）

改动摘要：

- `BLESecurityCommand`：`0x22` 的 `0x02/0x03/0x04` 帧构造、6 位 PIN 校验、状态解析；未实现
  BLE 侧 `0x05`（固件必拒）。
- `BLEManager`：
  - `didConnect` 不再置 `.connected`；改为保存 FFF1/FFF2 后调用 `setNotifyValue(true)`，
    订阅成功（`didUpdateNotificationStateFor` 且 `isNotifying`）才 `finalizeConnection()`。
  - 120 s 配对超时；失败映射 `authenticationFailed / staleBond / timeout / connectionFailed`；
    首次配对相关失败即设 `suppressAutoReconnect`，停止 1 s/2 s/4 s 重连风暴。
  - `didWriteValueFor` 捕获 `CBATTError.insufficientEncryption`（控制帧有回调；HID 的
    `.withoutResponse` 无回调，仍以 FFF1 订阅为唯一门禁）。
  - 安全命令窗口 `0x03/0x04/0x02`，5 s 超时，与改名/ECM 双向互斥（共享 `0xA2`）。
  - 解绑成功：清 `lastConnectedUUID/Name` + 本地 PIN 提示记录，抑制自动重连；等固件重启断开，
    3 s 内未断则主动断开。
  - 首次连接（本机记录为空）且未在 App 内改过 PIN 时提示"可能仍为 666666"。
  - PIN 不落盘、不写日志；`sendRawData` 仅记录字节数。
- UI：`Pairing & Security` 入口（锁图标）→ `BLESecuritySheet`（滚动布局、绑定槽状态、
  改 PIN、重置配对 + 三步交接）；连接弹窗新增配对中状态、配对失败告警卡、出厂 PIN 提醒横幅；
  设备列表底部常驻默认 PIN 说明。
- 本地化：6 语言新增 38 条键；`plutil` 校验通过。

未完成 / 待真机：第 0 步 spike、P1–P14 矩阵。模拟器无 BLE，无法在本地验证系统 PIN 弹窗、
LED 态与真实断连错误码。

### 14.1 真机反馈修正（2026-11-10 17:34）

现象：首次连接 `setNotifyValue` 约 4.8 s 后返回 `Encryption is insufficient (0x0F)`，App 判定
配对失败并断开；手动再连一次即成功。

原因：iOS 在收到 0x0F 后会完成配对（或丢弃旧固件遗留的失效 bond 后重新配对），但**不会自动重发
那次 CCCD 写入**，所以本次 `setNotifyValue` 只能以失败结束。固件与系统侧其实已经就绪。

修正：`didUpdateNotificationStateFor` 收到 FFF1 的 `insufficientEncryption` 且仍在配对窗口时，
延迟 500 ms 重新 `setNotifyValue` 一次（每条连接最多 1 次），成功即 `finalizeConnection`；
仍失败才映射为 `authenticationFailed`。这样首次连接无需用户手动重连。

附带修正：连接卡片 `.disconnected` 状态误用了不存在的 SF Symbol `bluetooth`（控制台报
`No symbol named 'bluetooth'`），改为 `antenna.radiowaves.left.and.right`。
