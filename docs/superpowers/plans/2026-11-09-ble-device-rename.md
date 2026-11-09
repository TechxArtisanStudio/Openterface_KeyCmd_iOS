# BLE 设备改名功能实施计划

> 日期：2026-11-09
> 状态：已实现，单元测试通过；待真机验证
> 范围：iOS App（KeyCmd）；固件侧能力已存在于 Openterface_KM，无需改固件

## 1. 目标

在 iOS App 中为已连接的 KVM-GO 设备提供"修改蓝牙名称"功能：

- 通过 BLE 直发 CH9329 扩展命令 `0x23` 修改设备广播名（固件持久化到 Flash）
- 支持恢复出厂名称（`0x31` + payload `0x00`，默认 "KVM-GO"）
- 改名后设备自动重启，App 自动重连并显示新名称

## 2. 协议事实（已核对固件源码）

来源：`Openterface_KM/APP/usbd_compostie_km.c`、`APP/peripheral.c`、
`docs/superpowers/specs/2026-09-20-ble-name-config-design.md`

### 2.1 帧格式（与 HID 相同的 CH9329 封装）

```
57 AB 00 <cmd> <len> <payload...> <checksum>
checksum = 前面所有字节累加 & 0xFF
```

| 操作 | 发送帧 | 成功响应 | 失败响应 |
|------|--------|----------|----------|
| 设置名称 | `57 AB 00 23 <n> <名字裸字节>` | `57 AB 00 A3 01 00 <sum>` | `57 AB 00 E3 01 <status> <sum>` |
| 恢复出厂 | `57 AB 00 31 01 00 <sum>` | `57 AB 00 B1 01 00 <sum>` | `57 AB 00 F1 01 <status> <sum>` |

**注意**：payload 是裸名字字节，**没有长度前缀**（设计文档 7.1 节的 Python 示例多了一个
len 字节，以固件 `usbd_compostie_km.c:325` 的实际 handler 为准）。

### 2.2 固件行为

- 名称限制 **1–20 字节**（UTF-8 按字节计；超长固件截断到 20，客户端应直接拒绝）
- 空 payload 或首字节 `0x00` → `STATUS_ERR_PARAM`
- 成功后固件更新广播数据并 **500ms 后自动重启**（`Peripheral_ScheduleSystemReset(500)`），
  BLE 连接必然断开，重启后以新名字广播
- 响应经 FFF1 notification 返回（`Peripheral_SetBleCh9329Response(1)` 路由）
- MiniKVM 无 BLE，本功能入口只在 BLE 已连接时出现，天然不可达

### 2.3 必须规避的坑

1. **0x23 载荷形状冲突**：固件用载荷形状区分 CH9329 改名与 BLE-Eth GET_ECM_IP
   （`peripheral.c` `Peripheral_IsBleEthEcmIpFrame`）：`len==1 且 payload[0]<=0x06`
   会被判给 ECM IP 查询。客户端校验规则：**所有字节 ≥ 0x20**（拒绝控制字符），
   一并覆盖首字节 0x00 的限制。
2. **扫描前缀过滤**：`BLEManager.didDiscover` 只收 `openterface/kvm/keymod` 前缀设备。
   改成任意名字后设备将扫不到 → 过滤抽为 `isDiscoverableDevice(name:identifier:)`，
   放行条件：已知前缀 **或** UUID 属于"已连接设备列表"（`ble_known_device_uuids`，
   连接时记录、手动断开不清除）**或** UUID 等于 `ble_last_connected_uuid`。
   注意：该列表只解决**本机**可发现性；其他手机仍需名字带已知前缀才能扫到。
3. **iOS 名称缓存**：重连后 `peripheral.name` 可能是旧缓存 → 改名流程用客户端提交的
   新名字更新 `ble_last_connected_name` 和 UI，不依赖 `peripheral.name`。
4. **重连风暴**：固件重启期间现有 1s/2s/4s 退避会耗尽 3 次尝试 → 改名路径不走
   `scheduleReconnect`，改为"断开后重新扫描，按 UUID 匹配自动连回"。

## 3. 改动清单

| 文件 | 改动 |
|------|------|
| `KeyCmd/Services/BLENameCommand.swift` | **新增**：纯逻辑（校验、拼帧、响应扫描器），无 CoreBluetooth 依赖，可单测 |
| `KeyCmd/Managers/BLEManager.swift` | 改名 API + 状态发布 + FFF1 响应拦截 + 重启后扫描重连 + 已知设备 UUID 列表与可发现性谓词 |
| `KeyCmd/View/Connection/ConnectionDialogView.swift` | 已连接时显示 "Rename Device" 入口 |
| `KeyCmd/View/Connection/RenameDeviceSheet.swift` | **新增**：改名表单（当前名、输入、字节计数、校验提示、恢复出厂、状态/错误显示） |
| `KeyCmd/Resources/Localizations/*/Localizable.strings` | 6 语言新增文案 |
| `KeyCmdTests/BLENameCommandTests.swift` | **新增**：拼帧/校验/扫描器单测 |

工程使用 Xcode 16 fileSystemSynchronizedGroups，新文件自动入 target，无需改 pbxproj。

## 4. 核心设计

### 4.1 BLENameCommand（纯逻辑）

```swift
enum BLENameCommand {
    static let maxNameBytes = 20
    static func validatedNameBytes(_ name: String) -> [UInt8]?  // trim；1...20 字节；全部 ≥0x20
    static func setNameFrame(_ name: String) -> Data?           // 0x23，校验失败返回 nil
    static func resetNameFrame() -> Data                        // 57 AB 00 31 01 00 34
    struct Response { cmd: UInt8; status: UInt8; isSuccess: Bool }
    struct ResponseScanner {                                    // 增量喂入 FFF1 字节
        // feed() -> (识别到的改名响应, 透传给 rawDataSubject 的其余字节)
        // 处理：半帧保留、非目标帧透传、垃圾字节透传、坏校验和逐字节滑窗
    }
}
```

### 4.2 BLEManager 状态机

```swift
enum RenameState: Equatable {
    case idle, sending, waitingForReboot, success
    case failure(RenameFailure)   // noResponse / rejected(UInt8) / disconnected / reconnectTimeout / notConnected
}
@Published private(set) var renameState: RenameState
```

流程：

1. `renameDevice(to:)` / `resetDeviceName()`：校验 → 置 `.sending` → `sendRawData` 发帧
   → 挂 5s 响应超时。内部状态切到 bleQueue 处理，与 delegate 回调同队列。
2. `didUpdateValueFor`(FFF1)：有 pendingRename 时字节进 `ResponseScanner`；
   命中 `A3/E3/B1/F1` → 处理响应（**不透传**给 rawDataSubject）；其余字节原样透传，
   终端隧道不受影响。
3. 响应成功：保存新名字到 `ble_last_connected_name` + 更新 UI 显示名，
   置 `.waitingForReboot`，记录 `renameRebootIdentifier`，等设备重启断连。
4. `didDisconnect`：若 awaitingRenameReboot → 不走 `scheduleReconnect`，
   置 `.reconnecting`，延迟 1s 后 `startScanning()`。
5. `didDiscover`：改名重启等待中且 identifier 匹配 → 直接 `beginConnecting`
   （绕过 autoConnect 开关与名字匹配）；同时扫描过滤放行已存 UUID。
6. `didConnect`：若 awaitingRenameReboot → 清标志、置 `.success`、
   用提交的新名字（而非缓存的 peripheral.name）落盘并更新 UI。
7. 整体重启重连超时 20s → `.failure(.reconnectTimeout)`。
8. 响应前断连 → `.failure(.disconnected)`；5s 无响应 → `.failure(.noResponse)`
   （旧固件不支持 0x23 时的表现）；E3/F1 → `.failure(.rejected(status))`。

### 4.3 UI

- `ConnectionDialogView`：连接状态下在蓝牙卡片下方加 "Rename Device" 行，点击弹 sheet。
- `RenameDeviceSheet`：ScrollView 包裹（矮窗口可滚动）；当前名称、TextField、
  `n/20` 字节计数、校验提示；Save / Reset to Factory Name 按钮；
  sending/waitingForReboot 显示进度文案；failure 显示本地化错误；
  success 自动 dismiss。onAppear 重置 renameState 为 idle。

### 4.4 本地化新增 key（6 语言）

"Rename Device"、"Device Name"、"New name"、"Reset to Factory Name"、
"The device will restart and reconnect automatically."、"Renaming..."、
"Waiting for device to restart..."、"Use 1–20 UTF-8 bytes. Control characters are not allowed."、
"No response from the device. Its firmware may not support renaming."、
"The device rejected the new name."、"Disconnected before the device confirmed the rename."、
"The device restarted but could not be found again. Please scan manually."、
"Connect to a device first."

## 5. 测试计划

### 单元测试（KeyCmdTests/BLENameCommandTests.swift）

- 拼帧：ASCII 名已知向量逐字节断言（含 checksum）；中文名按 UTF-8 字节
- 校验：空/纯空白拒绝；20 字节通过、21 字节拒绝；6 汉字(18B)通过、7 汉字(21B)拒绝；
  控制字符拒绝；首尾空白 trim
- reset 帧精确字节：`57 AB 00 31 01 00 34`
- 扫描器：完整响应；跨两次 feed 的半帧；非目标帧透传；头部垃圾透传；
  坏 checksum 滑窗恢复；响应与终端数据 interleaved
- 可发现性（`BLEManagerTests` 新增 5 个）：UUID 列表持久化/去重；前缀放行（含大小写）；
  改名后凭已知 UUID 放行；lastConnectedUUID 放行；手动断开后仍可发现（回归场景）

### 构建验证

- [x] `xcodebuild test -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` 编译通过
- [x] 新增 `BLENameCommandTests` 18 个测试 + `BLEManagerTests` 9 个（含 5 个可发现性测试）
      + `FrameParserTests` 4 个，共 31 个全部通过（2026-11-09，含 UUID 列表修复后的重跑）
- [x] 6 个 Localizable.strings 均通过 `plutil -lint`

### 真机验证（BLE 无法在模拟器验证，需硬件）

- [ ] 连接 KVM-GO → Rename Device → 输入新名 → 设备重启 → 自动连回 → 显示新名
- [ ] 断电重启后名字保持；系统蓝牙列表可见新广播名
- [ ] Reset to Factory Name → 恢复 "KVM-GO"
- [ ] 超长/控制字符输入被客户端拦截
- [ ] 改名期间终端若有活动连接，重启后隧道按既有逻辑 teardown，无卡死

## 6. 明确不做

- 本地别名（假名字）：广播名不变，语义混淆，不做
- 固件改动：能力已具备
- 读取当前设备名的新命令：用 App 已保存/连接缓存的名字展示即可