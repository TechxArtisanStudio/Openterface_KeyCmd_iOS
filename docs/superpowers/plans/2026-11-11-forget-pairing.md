# 忘记配对（App 侧重置 + 系统引导）

日期：2026-11-11
状态：已实现（2026-11-11），真机待验证
前置：[2026-11-10 BLE 配对码与绑定管理](2026-11-10-ble-pairing-pin.md)

## 1. 目标

改完配对码后，能快速回到“未配对”状态重新测试。

## 2. iOS 能力边界

| 能力 | 支持 | 结论 |
|---|---|---|
| App 删除 iOS 系统蓝牙绑定 | 否 | 只能引导用户到 设置 > 蓝牙 > 忽略此设备 |
| App 清自己的配对记录 | 是 | 清 `lastConnectedUUID/Name`、`pairedDeviceUUIDs`、`pinChangedUUIDs` |
| BLE 下发 `0x22 0x02` 清设备绑定 | 是 | 但会把 PIN 恢复 666666，不能用于测试自定义 PIN |

因此本功能定义为：**断开并清空 App 侧记录、停止扫描/自动重连，然后给出系统设置步骤**。
不发送 `0x22 0x02`，避免测试时把新 PIN 冲掉。

## 3. 实现

### 3.1 BLEManager

- 新增 `forgetPairing()`：
  - `bleQueue` 上执行，设置 `suppressAutoReconnect`，结束在途的改名/ECM/安全窗口；
  - `stopScanning()` + `cancelPeripheralConnection`；
  - 清除 `ble_last_connected_uuid/name`、`ble_paired_device_uuids`；
  - 保留 `ble_known_device_uuids`（避免自定义名设备失去可发现性）和
    `ble_pin_changed_device_uuids`（忘记配对不会重置设备 PIN，清掉会误报“可能仍是 666666”）；
  - 主线程复位 `connectionState / lastConnectedDeviceName / isWaitingForPairing / pairingIssue / showFactoryPINReminder / securityState`。
- 新增内部静态 `clearLocalPairingState()` 便于单测。
- `didDiscover` 的自动连接分支增加 `suppressAutoReconnect` 判断，避免清完状态后扫描立刻又连回去；
  手动点选设备走 `beginConnecting` 会复位该标志，不受影响。

### 3.2 BLESecuritySheet

- “修改配对码”下方新增“在此 iPhone 上忘记配对”区块：
  - 二次确认，说明会断开、停止扫描、清 App 记录，但 iOS 仍保留系统绑定；
  - 确认后显示结果页：系统设置步骤 + 设备名复制 + 返回 App 用新 PIN 重新配对；
  - 若设备仍拒绝配对，提示可能需要 USB 重置设备绑定。

### 3.3 出厂 PIN 提醒开关

- `BLEManager.factoryPINReminderKey` / `factoryPINReminderEnabled`：默认开启；
  `finalizeConnection` 的首次连接提醒增加该开关判断。
- `Settings > General` 新增“蓝牙配对”区块和“提醒我修改出厂配对码”开关。
- 提醒横幅挂在 `ContentView` 主界面顶层（顶栏下方，仅连接时显示）；`ConnectionDialogView`
  只负责连接，成功加密后会自动关闭，不能承载这条提醒。横幅带“Change”（直接打开
  `BLESecuritySheet`）和关闭按钮，开关关闭后同样立即隐藏。
- 重置配对成功页新增明确文案“配对码已恢复为 666666”；设备不支持读取当前 PIN，
  因此提醒只能在“首次连接且本 App 未改过 PIN”时给出一次性推断。
- 重连遇到 `CBError.peerRemovedPairingInformation`（设备侧已清绑定）时，清除本机
  `paired/pinChanged` 标记；本固件清绑定必然重置 PIN，因此下次连接会重新出现出厂提醒。
  这样 USB 侧执行 `0x22 0x02` 后 App 也能重新提醒。
- 通过“修改配对码”把 PIN 设成 `666666` 时不再记入 `pinChangedUUIDs` 并重新显示提醒；
  `setPIN` 只向 BLE 队列传一个布尔标记，PIN 明文不保留。

### 3.4 本地化

`en / zh-Hans / zh-Hant / ja / ko / fr` 追加 12 条文案。

## 4. 测试

- 单测：`clearLocalPairingState()` 清 3 个 key，保留 known UUID 与 PIN 改动标记。
- `plutil -lint` 校验 6 个 `Localizable.strings`。
- `xcodebuild test`（iPhone 17 Pro 模拟器）。
- 真机待验证：改 PIN → 忘记配对 → 系统设置忽略 → 重新扫描 → 输入新 PIN。

## 5. 文件清单

- [x] `KeyCmd/Managers/BLEManager.swift`
- [x] `KeyCmd/View/ContentView.swift`（顶层出厂 PIN 提醒横幅）
- [x] `KeyCmd/View/Connection/BLESecuritySheet.swift`
- [x] `KeyCmd/View/Connection/ConnectionDialogView.swift`
- [x] `KeyCmd/View/GeneralSettingsView.swift`
- [x] `KeyCmd/Resources/Localizations/*.lproj/Localizable.strings` × 6
- [x] `KeyCmdTests/BLEManagerTests.swift`
- [x] 本计划状态与勾选

## 6. 验证

- [x] `plutil -lint` 6 个 `Localizable.strings` 全部通过
- [x] `BLEManagerTests` 14 项通过（含忘记配对与出厂 PIN 提醒开关）
- [x] 全量 `xcodebuild test` 通过（406 tests, 0 failures）
- [ ] 真机：改 PIN → 忘记配对 → 系统设置忽略 → 重新扫描 → 输入新 PIN
- [ ] 真机：重置为 666666 → 重连 → 主界面出现修改 PIN 提醒 → Change 可直接改 PIN

## 7. 实施记录（2026-11-11）

- `BLEManager.forgetPairing()`：设 `suppressAutoReconnect`、停止扫描、断开连接；
  清 `lastConnectedUUID/Name`、`pairedDeviceUUIDs`，保留 `knownDeviceUUIDs` 和 `pinChangedUUIDs`；
  主线程复位连接/配对/安全状态。
- `didDiscover` 自动连接分支增加 `suppressAutoReconnect` 判断，避免忘记配对后扫描立即回连；
  手动点选设备仍正常。
- `BLESecuritySheet` 新增“在此 iPhone 上忘记配对”区块、二次确认和结果页（系统设置步骤、
  设备名复制、用新 PIN 重配提示）。
- 未发送 `0x22 0x02`：该命令会把 PIN 恢复为 666666，与“改完 PIN 再测试”的目标冲突。
- 新增 `factoryPINReminderEnabled` 开关（默认开），General 页可关闭出厂 PIN 提醒；
  重置成功页明确显示“配对码已恢复为 666666”。
- 设备侧清除绑定（`peerRemovedPairingInformation`）时同步清除本机 PIN 改动标记，
  使出厂提醒在 USB 重置后也能重新出现。
- 修复提醒不可见：`finalizeConnection` 设置提醒的同时关闭了连接弹窗，而横幅只在该弹窗内渲染。
  现改为 `ContentView` 顶栏下方的全局横幅（仅连接时显示），Change 直接打开 `BLESecuritySheet`；
  `ConnectionDialogView` 内重复横幅已删除。
- 修复“把 PIN 改成 666666 后不再提醒”：`setPIN` 成功时若新 PIN 就是 666666，
  不记入 `pinChangedUUIDs` 并重新置位提醒标记；只用布尔值传递，PIN 明文不保留。
- 修改 PIN 的确认文案从页面顶部移到 Save 按钮正下方（`BLESecuritySheet.pinSection`），
  避免用户停在按钮处时看不到成功提示。固件 `0x22 0x04` 只影响下一次配对、不断开现有
  绑定，因此改完 PIN 后本机直接重连属于预期行为。

## 8. 后续可选项（需固件配合）

若希望真正“一键清空两侧绑定且保留新 PIN”，需要固件新增“擦除 bond、保留 PIN override”的命令；
现有 `0x22 0x02` 无法满足。iOS 系统绑定仍只能由用户在 设置 > 蓝牙 中删除。

## 9. PIN 分享（2026-11-11 已实现）

- 入口：`Pairing & Security` 页新增常驻 `Pairing PIN` 区块；只要本机缓存过该设备的 PIN，
  随时可查看、`Copy` 或 `ShareLink`，不再要求先改 PIN。
- 原因：固件从不上报当前 PIN，App 只在用户输入并保存成功的那一刻知道 PIN。
  要实现“随时分享”，只能在本机缓存上次设置的值。
- 存储：`PairingPINStore`（Keychain，service `com.openterface.keycmd.pairing-pin`，
  account 为设备 UUID）。`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不参与同步，
  不写日志、不写 UserDefaults。仅缓存该 App 自己设置过的 PIN。
- 写入时机：
  - `0x22 0x04` 设置 PIN 成功 → 缓存新 PIN；
  - `0x22 0x02` 重置（含 `clearPairingHistory` 的 stale-bond 推断）→ 缓存 666666。
- “忘记配对”不删除缓存：设备 PIN 未变，而且“改 PIN → 忘记配对 → 重新配对”
  正需要这个值来查看/分享；与保留 `pinChangedUUIDs` 的语义一致。
  缓存只在设备侧真正重置时被覆盖为 666666。
- 过期风险：如果 PIN 被其他手机或 USB 改过，缓存无法感知；页面固定提示
  “Last PIN set by this app… may be out of date if changed elsewhere.”。
- 保存成功时仍在 Save 按钮下方显示 “Pairing PIN updated.”，同时 `Pairing PIN` 区块
  立即换成新值；开始下一次保存时会短暂进入 `.savingPIN`。
- 本地化：新增 `Pairing PIN` 与过期说明；移除原来“PIN 只保留在本页”的文案。
- 验证：`PairingPINStoreTests` 覆盖保存/更新/删除/按设备隔离；全量 `xcodebuild test` 通过。
- 真机待验证：改 PIN → 杀进程 → 重开 → Pairing & Security 仍可分享；忘记配对 → 缓存仍在（设备 PIN 未变）。

## 10. 设备标识符扫描（2026-11-11 已实现）

- 问题：原发现逻辑要求广播名以 `openterface` / `kvm` / `keymod` 开头，
  用户改成任意名称（如 `MyDevice`）后设备不再出现在扫描列表。
- 固件事实（`APP/peripheral.c`）：`advertData` 在追加运行时名称之前，固定写入
  `GAP_ADTYPE_16BIT_MORE` + `SIMPLEPROFILE_SERV_UUID`（`0xFFF0`，
  `Profile/include/gattprofile.h`）。名称最长 20 字符且可改，服务 UUID 不变。
- iOS 通过 `CBAdvertisementDataServiceUUIDsKey` 读取该 UUID，与设备名称无关。
- 实现：
  - `BLEManager.serviceUUID = CBUUID(string: "FFF0")`，`discoverServices` 复用同一常量。
  - `isDiscoverableDevice(name:identifier:advertisedServices:)`：先判断广播中是否含
    `FFF0`，含则直接接受任意名称；名称前缀仅作为旧固件未广播该 UUID 时的兼容回退；
    最后仍接受 `lastConnectedUUID` / `knownDeviceUUIDs`。
  - `didDiscover` 从 `advertisementData[CBAdvertisementDataServiceUUIDsKey]` 取出
    广播服务并传入判定。
  - `shouldAutoConnect`：已知设备 UUID 直接自动连接；名称比较优先用广播名，
    避免 iOS 缓存的 `peripheral.name` 在改名后过期。
  - 扫描本身仍不过滤服务：旧固件若未广播 `FFF0` 仍能靠名称前缀被发现。
- 已知取舍：`0xFFF0` 是常见实验用服务 UUID（例如 HM-10 模块）。这类设备可能
  出现在扫描列表，但连接后因缺少 `FFF1/FFF2` 会失败；这是 iOS 无法读取 MAC 地址
  条件下可用的最稳定标识。
- 测试：`testDiscoverableByAdvertisedServiceUUIDForAnyName` 覆盖任意名称 + `FFF0`
  可发现、外来服务仍被拒绝。

