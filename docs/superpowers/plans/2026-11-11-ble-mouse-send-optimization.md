# BLE 鼠标发送链路优化（iOS 端）

日期：2026-11-11
状态：已实现（2026-11-11），真机矩阵待验证
目标产品：KeyMod / KVM-GO 等 `ENABLE_BLE` 机型
关联计划：[BLE 配对码](2026-11-10-ble-pairing-pin.md)

## 1. 背景

触摸板/陀螺仪/按键的 HID 报文都从同一条路径发出：

```
TouchpadView.handlePan
  → MouseManager.handleDragChanged（构建 11 字节 CH9329 鼠标报文）
  → BLEManager.sendTouchData(data:)
  → CBPeripheral.writeValue(_:for:type: .withoutResponse)
```

键盘、点击、滚轮、按住按键也走 `sendTouchData`，但频率低。拖动路径是 60–120 Hz 的持续写入，
因此它决定了"跟手性"和功耗表现。当前实现有三处明显问题。

## 2. 现状问题

### 2.1 每帧都生成 hex 日志（热路径最大开销）

[BLEManager.swift:1056](file:///Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/BLEManager.swift#L1056)：

```swift
connectedPeripheral.writeValue(data, for: fff2Characteristic, type: .withoutResponse)
let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
logger.logHex(hexString, message: "TX: ", category: "BLE", level: .debug)
```

每帧：11 次 `String(format:)` + 拼接 + `log()` 内的字符串插值 + `Date()` + `DateFormatter`，
再进入 [LogManager.swift:36](file:///Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/LogManager.swift#L36)
的 `barrier` 串行队列。日志队列被鼠标拖动占满后，其他模块的关键日志（配对、ECM、SSH）
会明显延迟。这些 debug 帧数据在正式使用中无诊断价值。

### 2.2 无背压、无合并

`writeValue(.withoutResponse)` 连续按触摸事件率提交。iOS 单个连接间隔（约 15 ms）只能完成
约 1 次 GATT 操作，事件率更高时数据堆在 CoreBluetooth 内部：

- 光标"慢半拍"，松手后仍在追赶；
- 未实现 `peripheralIsReadyToSendWriteWithoutResponse` 与
  `CBPeripheral.canSendWriteWithoutResponse` 判断；
- 没有合并相邻相对位移（相对位移可加和，合并完全无损）。

### 2.3 ±127 截断直接丢位移

[MouseManager.swift:38](file:///Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/MouseManager.swift#L38)：

```swift
xDelta *= 4
let boundedXDelta = Int8(max(-127, min(127, xDelta)))
```

[GyroMouseManager.swift:185](file:///Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/GyroMouseManager.swift#L185)
同样在发送前 clamp 到 ±127。超出部分被永久丢弃，手指划得越快光标越跟不上；陀螺仪快速转动时同理。

### 2.4 其他

- [BLEManager.swift:1235](file:///Users/txa/project/Openterface_KeyCmd_iOS/KeyCmd/Managers/BLEManager.swift#L1235)
  的 `sendMouseMove(dx:dy:)` 全项目无人调用（死代码，且同样截断）。
- `sendTouchData` 直接从调用线程写 BLE，没有统一的 HID 写队列；离散报文与移动报文的顺序
  依赖 CoreBluetooth 内部队列。

## 3. 设计

### 3.1 不变量

1. **离散事件（点击、按键、滚轮、按钮状态切换）必须立即发送**，不参与合并、不被延迟。
2. **纯相对移动可以合并**：同一按钮状态下的 (dx, dy) 直接相加；按钮状态变化时先 flush 旧位移。
3. **位移不丢失**：累计值超过 ±127 时拆成多帧，直到发完。
4. **尊重链路背压**：`canSendWriteWithoutResponse == false` 时停止发送，保留累计值，
   等 `peripheralIsReadyToSendWriteWithoutResponse` 回调再发。
5. **断连清理**：连接切换/断开时丢弃未发送的累计位移，避免重连后把旧位移补发出去。
6. 配对门禁不变：只有 `connectionState == .connected`（FFF1 已订阅、链路已加密）才发送。

### 3.2 BLEManager：HID 写调度器

新增私有队列与状态（全部只在 `hidWriteQueue` 上读写）：

```swift
private let hidWriteQueue = DispatchQueue(label: "com.keycmd.hid.write", qos: .userInteractive)
private var pendingMoveDx = 0
private var pendingMoveDy = 0
private var pendingMoveButtons: UInt8 = 0
private var pendingPeripheral: CBPeripheral?
private var pendingCharacteristic: CBCharacteristic?
```

公开 API：

```swift
/// 合并相对位移，按链路能力发送；deltas 不做 ±127 截断。
func sendMouseMove(dx: Int, dy: Int, buttons: UInt8 = 0)

/// 离散 HID 报文（已有 API）：先 flush 待发位移，再立即写入。
func sendTouchData(data: Data)
```

纯函数（可单测）：

```swift
/// 从累计值中取出一个 CH9329 步长（±127），并扣减累计值。
static func nextMouseStep(dx: inout Int, dy: inout Int) -> (dx: Int8, dy: Int8)?
```

发送逻辑：

```
sendMouseMove(dx, dy, buttons):
  guard dx != 0 || dy != 0
  capture peripheral / FFF2 on caller thread
  hidWriteQueue.async:
    if buttons != pendingMoveButtons:
        flushPendingMoves()          // 用旧按钮状态发完
        pendingMoveButtons = buttons
    pendingMoveDx += dx; pendingMoveDy += dy
    pendingPeripheral = peripheral; pendingCharacteristic = fff2
    flushPendingMoves()

flushPendingMoves():
  while (pendingDx != 0 || pendingDy != 0)
        && peripheral.canSendWriteWithoutResponse
        && sent < safetyCap:
      (sx, sy) = nextMouseStep(&pendingDx, &pendingDy)
      write Keymod.buildMouseRel(buttons: pendingMoveButtons, dx: sx, dy: sy, wheel: 0)
        with .withoutResponse
  if still pending due to safetyCap: hidWriteQueue.async { flushPendingMoves() }
  if fully drained: clear pendingPeripheral/Characteristic
```

`peripheralIsReadyToSendWriteWithoutResponse(_:)` → 切到 `hidWriteQueue` 调 `flushPendingMoves()`。

`sendTouchData(data:)`：

```
capture peripheral / FFF2, guard connectionState == .connected
hidWriteQueue.async:
  flushPendingMoves()            // 尽量先发完移动
  dropPendingMovesIfUnsatisfied  // 链路仍忙则丢弃旧位移，保证离散事件不排队
  peripheral.writeValue(data, for: fff2, type: .withoutResponse)
```

丢弃而不是等待的原因：鼠标报文里的按钮是**绝对位掩码**，离散报文超越几帧旧位移不会改变
语义；而点击/按键延迟是可感知的。

日志：删除每帧 hex；仅在无法发送（未连接/FFF2 缺失）时记录一次错误。

### 3.3 调用方改动

- `MouseManager.handleDragChanged`：不再自建报文、不再 clamp，改为
  `bleManager.sendMouseMove(dx: Int(delta.x) * 4, dy: Int(delta.y) * 4, buttons: buttons)`。
- `GyroMouseManager.sendMouseMovement`：改为 `sendMouseMove(dx:dx, dy:dy)`，
  `clampMouseDelta` 改为四舍五入（不再截断）。
- 点击/双击/滚轮/按住按键/键盘保持 `sendTouchData`，行为不变（离散、立即）。
- 删除旧 `sendMouseMove(dx:dy:)` 的截断实现，替换为新签名。

### 3.4 明确不做

- 不改 CH9329 帧格式、不改 FFF2 写入类型（HID 仍用 `.withoutResponse`）。
- 不改 BLE-Eth 隧道的 `.withResponse` + 128 字节分片逻辑（那条路径有固件侧 ACK 要求）。
- 不引入定时器节流：以 `canSendWriteWithoutResponse` 为唯一节流依据，空闲时零延迟。
- 不改点击序列的 50/100 ms 固定延时。

## 4. 文件清单

- [x] `KeyCmd/Managers/BLEManager.swift`（HID 写队列、合并、拆帧、背压、ready 回调、去日志、断连清理）
- [x] `KeyCmd/Managers/MouseManager.swift`（拖动走 `sendMouseMove`，去掉截断）
- [x] `KeyCmd/Managers/GyroMouseManager.swift`（同上，去掉截断）
- [x] `KeyCmdTests/BLEManagerTests.swift`（`nextMouseStep` 单测）
- [x] 本计划文档状态回填

## 5. 测试

### 5.1 单元测试

`nextMouseStep`：

- `(200, -300)` → 首帧 `(127, -127)`，剩余 `(73, -173)`；
- 循环取尽后，所有步长之和等于原始累计值（符号与总量守恒）；
- `(-127, 0)` → 恰好 `(-127, 0)`，剩余 0；
- `(5, 0)` → `(5, 0)`；下一次返回 `nil`；
- `(0, 0)` → `nil`；
- `(127, 127)` 与 `(-126, 126)` 边界。

### 5.2 构建

```bash
xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### 5.3 真机矩阵（KeyMod）

| # | 用例 | 预期 |
|---|---|---|
| M1 | 慢速拖动 | 光标连续、无抖动 |
| M2 | 快速大幅滑动 | 不再落后于手指；松手后无持续漂移 |
| M3 | 拖动中点击/长按 | 点击位置正确，无丢点击 |
| M4 | 拖拽保持（按住） | 按钮状态切换后方向正确 |
| M5 | 双指滚动 + 拖动交替 | 滚动与移动互不粘连 |
| M6 | 陀螺仪快速转动 | 光标跟手，不再截断 |
| M7 | 断开/重连后立即操作 | 不会补发断连前的旧位移 |
| M8 | 连续拖动 30 s | CPU 占用明显下降（无逐帧日志） |

## 6. 风险

| 风险 | 处置 |
|---|---|
| 合并引入额外延迟 | 不做定时器；链路空闲时事件到达即发，忙时才合并 |
| 离散报文与移动顺序 | 同一 `hidWriteQueue`；离散发送前先 flush，链路忙则丢弃旧位移 |
| `canSendWriteWithoutResponse` 长期为 false | 等 ready 回调；配对超时/断连会清理状态，不会永久卡住 |
| 大位移拆帧造成"追尾" | 以链路实际能力发送，总量守恒；比截断丢失更符合用户预期 |
| 线程竞争 | pending 状态只在 `hidWriteQueue` 上访问；peripheral/characteristic 在调用线程捕获后传入 |
| 旧固件/未配对 | 发送前仍要求 `.connected`（FFF1 已订阅），未加密不发 |

## 7. 实施顺序

1. **P1**：`nextMouseStep` + 单测（纯函数，先锁定拆帧语义）。
2. **P2**：`BLEManager` HID 调度器、去逐帧日志、ready 回调、断连清理。
3. **P3**：`MouseManager` / `GyroMouseManager` 切换到 `sendMouseMove`。
4. **P4**：全量测试 + 更新本计划勾选与实施记录。

## 8. 验收

- [x] `nextMouseStep` 单测通过
- [x] 全量 `xcodebuild test` 通过（395 tests, 0 failures）
- [x] 拖动路径不再产生逐帧 hex 日志
- [x] 快速滑动位移守恒（单测覆盖）
- [x] 离散事件仍立即发送，按钮状态正确
- [ ] 真机矩阵 M1–M8 通过（真机待验证）
- [x] 本计划状态与勾选更新

## 9. 实施记录（2026-11-11）

- `BLEManager`：
  - 新增 `hidWriteQueue`（serial, `.userInteractive`），所有 HID 报文串行写入；
  - 新增 `sendMouseMove(dx:dy:buttons:)`：累计相对位移，按钮状态变化时先 flush；
  - `nextMouseStep` 纯函数按 ±127 拆帧，位移总量守恒；
  - `flushPendingMoves` 以 `CBPeripheral.canSendWriteWithoutResponse` 为唯一节流依据，
    每轮最多 32 帧后让出队列；`peripheralIsReady(toSendWriteWithoutResponse:)` 继续发送；
  - 离散报文 `sendTouchData`：先 flush 位移；链路仍忙则丢弃旧位移后立即写入，避免点击延迟；
  - 连接开始/主动断开/意外断开时 `discardPendingMoves()`，重连不补发旧位移；
  - 删除 `sendTouchData` 的逐帧 hex 日志（改为零日志热路径）。
- `MouseManager.handleDragChanged`：直接发送未截断的 `delta × 4`，零位移事件不再发空帧。
- `GyroMouseManager`：`clampMouseDelta` 改名 `roundedMouseDelta`，只做四舍五入，不再截断。
- 单测：`nextMouseStep` 的余量、总量守恒、正负边界、零位移共 3 个用例。

真机待验证：M1–M8（尤其是快速滑动跟手性、拖动中点击位置、断连重连无旧位移补偿）。
模拟器无 BLE，无法验证实际链路节流效果。
