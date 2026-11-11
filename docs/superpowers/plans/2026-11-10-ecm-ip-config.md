# ECM IP 配置功能（获取 / 更改）

日期：2026-11-10
状态：实现完成（含 SSH 终端集成 + SSH 隧道连不上修复 §11），374 个单元测试全部通过；待真机验证

## 1. 目标

在 iOS App 中查看和修改 KeyMod 设备（Openterface_KM 固件）的 ECM 桥接网络配置（5 个参数），
并支持恢复默认值。全部通过蓝牙（BLE-Eth）完成。
入口放在连接对话框（与"修改设备名称"并列），仅 BLE 已连接时可见。
SSH 终端新建连接配置时，默认主机自动使用从设备读取的目标机 IP（见 §10）。

> 命名说明：产品/固件是 KeyMod（仓库 Openterface_KM）；固件默认 BLE 广播名仍为
> "KVM-GO"（peripheral.c:101 BLE_DEVICE_NAME），改名功能的恢复默认值沿用该广播名。

## 2. 协议（已对照固件源码核实）

来源：`Openterface_KM/APP/ble_eth_protocol.c`（SET/GET_ECM_IP handler）、
`APP/include/ble_eth_protocol.h:45-54`（状态码）。iOS 走 BLE-Eth 层（FFF2 写 / FFF1 通知），
不走 CH9329 0x26/0x27（那是 USB/UART 通道用的等价命令）。

帧格式与 BLENameCommand 相同：`57 AB 00 <cmd> <len> <payload...> <sum8>`。

### GET — cmd 0x23

请求 payload：`[sub_cmd]`，本功能只用 `0x00`（读全部）。
响应 cmd **0xA3**，payload：`[status 1B][host_ip 4][dev_ip 4][mask 4][target_host_ip 4][target_dev_ip 4]`（共 21B）。

> 注意：0x23 + 单字节 payload(0x00..0x06) 被固件判别为 BLE-Eth GET_ECM_IP；
> 改名 SET_NAME 也是 0x23 但 payload ≥ 2 字节（名称 UTF-8），两者不冲突。
> **响应 cmd 0xA3 与改名成功响应相同** → 改名窗口与 ECM 窗口必须互斥（见 §4）。

### SET — cmd 0x22

| sub_cmd | payload | 说明 |
|---|---|---|
| 0x00 | `[00][host 4][dev 4][mask 4][target_host 4][target_dev 4]` = 21B | 设置全部（本功能使用） |
| 0x04 | `[04]` = 1B | 恢复默认 |

（0x01/0x02 部分设置本功能不用；0x03 被 CH9329 bond-count 占用，固件刻意跳过。）
响应 cmd **0xA2**，payload：`[status 1B]`。

### 状态码

- `0x00` 成功
- `0xE5` 参数错误（校验失败）
- `0xE9` 内部错误（Flash 擦写失败）

### 校验规则（固件 ECM_IPConfig_Validate，App 端镜像实现）

1. 4 个 IP 均不为 0.0.0.0 / 255.255.255.255
2. 掩码为连续 1 后跟连续 0，且非 0.0.0.0 / 255.255.255.255
   > 陷阱：ecm-ip-config-design.md 里的公式 `(~m+1) & m == 0` 是错的（会拒绝合法的
   > 255.255.255.0）。固件实际实现（ecm_ip_config.c:49-50）为 `inv = ~m; inv & (inv+1) == 0`，
   > App 端已按源码实现。
3. host/dev/target_host/target_dev 全部同子网（按掩码与运算）
4. 4 个 IP 互不相同

### 默认值

host 192.168.11.1 / dev 192.168.11.3 / mask 255.255.255.0 /
target_host 192.168.11.2 / target_dev 192.168.11.5

### 生效时机

写入成功后固件约 500ms 后对相应侧 USB 做软重枚举，**无需重启、BLE 连接不受影响**。
UI 提示"网络会短暂重新连接"。

## 3. 命令层：`KeyCmd/Services/ECMIPCommand.swift`（新增）

纯逻辑 enum，仿 BLENameCommand：

- `struct Config: Equatable`：5 个 `[UInt8]`（各 4 字节）字段
  `hostIP / devIP / subnetMask / targetHostIP / targetDevIP`
- `static let defaultConfig`
- `static func parseIPv4(_ String) -> [UInt8]?` / `formatIPv4(_ [UInt8]) -> String`
- `static func validate(_ Config) -> Bool`（镜像固件 4 条规则）
- `static func getFrame() -> Data`（0x23 [0x00]）
- `static func setAllFrame(_ Config) -> Data?`（先 validate；0x22 [0x00]+20B）
- `static func resetFrame() -> Data`（0x22 [0x04]）
- `static func parseConfig(_ payload: Data) -> Config?`（GET 响应去掉 status 后的 20B）
- 拼帧复用 `BLENameCommand.frame(cmd:payload:)`

### 共享扫描器扩展

`BLENameCommand.ResponseScanner.Response` 增加 `payload: Data` 字段
（status 字节之后的数据；改名响应为空）。扫描逻辑本身不变，
ECM 用 `ResponseScanner(targetCommands: [0xA2, 0xA3])` 复用，避免重复 60 行解析代码。
更新 BLENameCommandTests 中 2 处 `Response(cmd:status:)` 构造。

## 4. BLEManager 接入

仿改名流程（bleQueue 串行 + @Published 状态 + 5s 超时 + scanner flush）：

```swift
enum ECMIPState: Equatable {
    case idle, fetching, fetched(ECMIPCommand.Config), saving
    case failure(ECMIPFailure)
}
enum ECMIPFailure: Equatable {
    case notConnected, busy, noResponse, rejected(UInt8), invalidResponse, disconnected
}
```

> 实现调整：不设 `.saved` 状态 —— SET 成功（0xA2 status 0）后管理器自动链式发 GET 回读，
> 状态保持 `.saving` 直到 `.fetched(config)`，UI 字段始终回填设备真实持久化的值。

- `@Published private(set) var ecmIPState: ECMIPState = .idle`
- 私有：`ecmScanner`、`pendingECMRequest`（get/set）、`ecmResponseTimeout`
- `fetchECMIP()`：guard 已连接 + fff2 + **无改名在途**（renameScanner/pendingRenameName/renameRebootIdentifier 均空，否则 .failure(.busy)）→ 装 scanner → 发 GET → 5s 超时
- `saveECMIP(_ config)` / `resetECMIP()`：同样 guard → 发 SET → 成功后自动再 fetch 一次刷新显示
- `dismissECMIPResult()`：failure → idle
- **互斥**：`beginRename` 增加 guard `ecmScanner == nil`（ECM 在途时拒绝改名）
- `didUpdateValueFor` 路由：renameScanner 优先 → 否则 ecmScanner → 否则 rawDataSubject（隧道不受影响）
- 断连清理：ecmScanner flush + 状态置 failure(.disconnected)（仅当有在途请求）
- 响应处理：0xA2 + status 0 → 链式发 GET 回读（重新计 5s 超时）；0xA3 + status 0 + 20B → parseConfig → .fetched；
  status ≠ 0 → .failure(.rejected(status))；0xA3 数据长度错误 → .failure(.invalidResponse)

## 5. UI

### 入口：ConnectionDialogView

"修改设备名称"行下方新增"ECM 网络"行（network 图标），仅 connected 时显示，
点击弹出 `ECMIPSheet`。

### `KeyCmd/View/Connection/ECMIPSheet.swift`（新增）

仿 RenameDeviceSheet：NavigationView + ScrollView（矮窗口可滚动）：

- onAppear → `fetchECMIP()`，显示 ProgressView
- fetched 后显示 5 个 TextField（等宽字体、decimalPad 不适用 → 默认键盘 + 关闭 autocorrect/capitalization）：
  - 主机侧 IP（host_ip）— "主机（Mac/PC）的 IP"
  - 设备主机侧 IP（dev_ip）
  - 子网掩码
  - 目标机 IP（target_host_ip）
  - 设备目标侧 IP（target_dev_ip）
- 实时校验：任一字段非法或整体 validate 失败 → 红色提示 + Save 禁用
- Save 按钮 → `saveECMIP`；saving 时禁用编辑与关闭（interactiveDismissDisabled）
- "恢复默认配置"按钮（红色）→ confirmationDialog 确认 → `resetECMIP()`
- 状态行：fetching/saving 进度、failure 原因（含 0x%02X 状态码）；加载失败时显示 Retry 按钮
- 说明文字："修改立即生效，网络会短暂重新连接。所有 IP 必须在同一子网且互不相同。"
- fetched 后用设备返回值回填字段（保存/恢复默认成功后自动回读，字段即确认）

## 6. 本地化（6 语言）

en / zh-Hans / zh-Hant / ja / ko / fr 的 Localizable.strings 追加：
入口行、标题、5 个字段标签与说明、校验提示、按钮、状态与错误文案、确认对话框、生效说明。
键名用英文原文（与现有 "Rename Device" 模式一致）。

## 7. 测试

`KeyCmdTests/ECMIPCommandTests.swift`（新增）：

- 拼帧：GET / SET all / reset 的完整字节（含 checksum）逐字节断言
- parseConfig：20B → Config 往返；长度不足返回 nil
- parseIPv4 / formatIPv4：合法、非法（段数、>255、空段、非数字）
- validate：默认值通过；跨子网拒绝；重复 IP 拒绝；非连续掩码拒绝；
  0.0.0.0 / 255.255.255.255 拒绝；掩码 0/全 1 拒绝
- setAllFrame 非法 config 返回 nil
- 扫描器（targetCommands [0xA2,0xA3]）：GET 响应跨通知分片、payload 提取、
  隧道帧 passthrough、坏校验和透传

更新 `BLENameCommandTests`：Response 构造加 `payload:`。

验证：`xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
（完整日志写文件，不 pipe tail）。

## 8. 文件清单

新增：
- [x] KeyCmd/Services/ECMIPCommand.swift
- [x] KeyCmd/View/Connection/ECMIPSheet.swift
- [x] KeyCmdTests/ECMIPCommandTests.swift

修改：
- [x] KeyCmd/Services/BLENameCommand.swift（Response + payload 字段）
- [x] KeyCmd/Managers/BLEManager.swift（ECM 流程 + 互斥 + 路由）
- [x] KeyCmd/View/Connection/ConnectionDialogView.swift（入口行）
- [x] 6 × Localizable.strings
- [x] KeyCmdTests/BLENameCommandTests.swift（Response 构造）
- [x] ~~KeyCmd.xcodeproj/project.pbxproj~~ 无需修改：项目使用 Xcode 16 fileSystemSynchronizedGroups，新文件自动纳入（已有未提交的版本号 16→17 改动不属于本功能）

## 9. 验证清单

- [x] 单元测试全部通过（372 个，含 21 个新增 ECMIPCommandTests；2026-11-10）
- [x] 模拟器构建成功（xcodebuild test, iPhone 17 Pro）
- [ ] UI 走查（需真机 BLE 连接）：入口 → 获取 → 编辑 → 校验提示 → 保存 → 恢复默认
- [ ] 真机（KeyMod）：GET 返回默认值；SET 10.0.0.x 网段成功且 GET 回读一致；
      非法配置被拒（0xE5）；恢复默认成功；改名与 ECM 操作互斥不串扰
- [ ] SSH 终端（BLE-Eth 隧道）在 ECM 操作期间保持可用
- [ ] 改 IP 后新建 SSH profile 默认主机为新目标 IP，SSH 连接成功

## 10. SSH 终端集成（2026-11-10 追加）

用户需求：用蓝牙获取/更换 IP 后，SSH 终端要能连上 —— 终端默认主机必须跟随设备当前目标 IP。

- `BLEManager.lastECMIPConfig: ECMIPCommand.Config?`（@Published）：每次 GET 回读成功更新
- `TerminalViewModel.defaultSSHHost`：lastECMIPConfig.targetHostIP 格式化，未读取过时
  回退固件默认 192.168.11.2
- `TerminalViewModel.refreshECMIPConfig()`：BLE 已连接时发 GET
- 终端 `ConnectionDialog.onAppear`：loadProfiles + refreshECMIPConfig（打开连接对话框
  即从设备刷新一次目标 IP）
- `ProfileEditorSheet.defaultHost` 参数（带默认值，CredentialSettingsView 调用点不受影响）：
  新建 profile 的 host 默认值由硬编码 "192.168.11.2" 改为 defaultHost
- 已保存的 profile 不自动改写（用户数据）；改网段后需编辑旧 profile 或新建

## 11. SSH 隧道连不上修复（2026-11-10 追加）

现象：KeyCmd iOS 经 BLE-Eth 隧道 SSH 连接失败/卡死。对照可正常工作的参考实现
`/Users/txa/project/Opf_test`（PyQt6 + paramiko，`src/ble/eth_tunnel.py`）定位到
`KeyCmd/Services/BleEth/BleEthTransport.swift` 两个根因：

### Bug 1 — banner 竞态（入站）
`handleConnectResponse` 原先只 `signal()` semaphore，`running`/`connId` 要等
`connect()` 线程被唤醒后才设置。但设备在 CONNECT_RESP 之后立刻在**同一串行
bleQueue** 上推送 SSH banner，`deliverReassembledData` 此时看到 `running==false`
直接丢弃 → libssh2 永远等不到 banner。
修复：把 `connId`/`running` 的设置移进 `handleConnectResponse`（status==0 时，
持 stateLock，在 signal 之前）。因入站串行，banner 到达时状态已就绪，直接投递给
已挂载的 bridge listener。无需额外缓冲。

### Bug 2 — 无 ACK 流控/重传（出站）
原实现 DATA 分片直发（fire-and-forget，仅 5ms 间隔），`handleDataResponse` 把固件
元数据 ACK 全部丢弃。固件重装配/TX 队列只有 ~6 片余量，无 pacing 会溢出 → 静默丢包
→ 握手卡死。
修复（移植 Opf_test `_send_with_acks`/`_await_ack`/`_handle_ack`）：
- 解析 5B ACK `[status][conn][seq][expected_seq][rx_window]`（兼容 1B/4B）；
  `expected_seq` 累积确认，释放所有 `seq < expected` 的等待者，无命中再按精确键兜底
- `rxWindow = max(1,min(ack[4],15))`，发送窗口 `max(1,min(rxWindow,6))`
- 每片注册 `AckFuture`（CheckedContinuation）后再发；超时 `2s × 2^attempt`、
  最多 3 次重传，**原样重发同一帧**（固件重装配被超前分片作废）；重试用尽 →
  `onError` + `disconnect`
- 出站消息按 `SAFE_MESSAGE_LEN=1440` 切分（固件把一条重装配消息当作一个 TCP 段，
  超 MTU 余量会被丢）；单分片仍用 flags `0x41`（设备丢弃 count=0，见既有回归测试）
- `disconnect()`/`connect()` 重置时唤醒所有等待者（`.aborted`），输出读取器退出

新增回归测试（BleEthTransportTests）：
- `testBannerDeliveredImmediatelyAfterConnectResponse`：喂 CONNECT_RESP 后立即喂
  banner DATA_PUSH，断言 listener 收到（修复前会丢）
- `testMetadataAckNotDeliveredAsData`：5B ACK 不被当作入站数据投递

验证：全量 `xcodebuild test`（iPhone 17 Pro）→ **TEST SUCCEEDED，374 个测试 0 失败**
（含 2 个新增回归测试），日志 `/tmp/keycmd_ssh_fix.log`。
真机复测路径：KeyMod → 终端 → 新建/选择 profile（主机=设备目标 IP）→ SSH 连接，
观察日志出现 `DATA ACK ... window=` 与 banner 投递、握手完成。

## 12. 真机 CONNECT 阶段超时诊断（2026-11-10 追加）

真机日志（连接 192.168.20.2:22）：cleanup DISCONNECT 正常收到 0x92，CONNECT 帧
（cmd 0x10，12B，withResponse）发出后设备 **30s 内无任何 CONNECT_RESP** → KeyCmd 超时。
此问题在 banner/ACK 之前，属 CONNECT 建立阶段。

对照固件 `ble_eth_protocol.c`：
- 合法 CONNECT **不立即回应**：先 `ARP_PENDING` 发 ARP，ARP 应答后 `SYN_SENT` 发 SYN，
  TCP 建立（SYN+ACK）才回 `CONNECT_RESP SUCCESS`（:1811）。
- ARP/SYN 无应答时由 `BLE_Eth_PeriodicTick`（每秒 1 次，peripheral.c
  `SBP_PERIODIC_EVT_PERIOD=1600`×625µs=1s）重试：`SYN_RETRY_TICKS=10`、
  `SYN_MAX_RETRIES=5` → ARP 全超时约 **60s** 才回 `TIMEOUT(0xE1)`。
- 状态码：SUCCESS 0x00 / TIMEOUT 0xE1 / PARAM_ERR 0xE5 / FRAME_ERR 0xE6 /
  CONN_FULL 0xE7 / NO_ROUTE 0xE8。

根因：**目标 192.168.20.2 在设备 ECM 网段不可达**（无 ARP 应答）；且 KeyCmd 原
CONNECT 超时 30s < 固件 ~60s 预算，提前放弃，掩盖了真实的 0xE1/0xE8 判定。
CONNECT 拼帧与 Opf_test 完全一致（IP4+port2 大端），非拼帧 bug。

代码改进（让真实判定可见，不改变可达性本身）：
- `TerminalViewModel.connect`：timeoutMs 30000 → **65000**，覆盖固件 ARP 预算
- `BleEthTransport`：新增 `lastConnectError`（connect 失败时记录可读原因），
  `connectStatusText` 翻译 0xE1/0xE8/0xE7/0xE5；ViewModel 失败界面显示该原因
  而非笼统 "Transport connection failed"

用户侧需确认（真正解决办法）：
- KeyMod 的 USB ECM 口所连电脑的 ECM 网卡 IP 是否确为 192.168.20.2
- 设备 dev_ip 与目标是否同网段（掩码一致）
- 目标电脑 SSH 服务已开、防火墙放行 22

验证：全量 `xcodebuild test`，日志 `/tmp/keycmd_connect_timeout.log`。

## 13. 0xE1 根因证实：固件 target 侧 self-MAC 冲突（2026-11-10）

用户反馈「target 就是本地电脑、Mac 上已有 192.168.20.2、Opf_test 之前能连」，
要求复查代码。用 Opf_test 的工作代码做无界面探针（`/tmp/probe_tunnel.py`，复用
`ble.eth_tunnel.BleEthTunnel` + bleak），直连用户实际设备 keymod-test
（`11E6C99D-…`，INFO features=31）实测：

- `get_info` / `link_ping(0x1E)` 均正常 → BLE-Eth 通路好。
- GET ECM（0x23）回读配置正确：host 192.168.20.1 / dev .20.3 / mask /24 /
  **target_host .20.2 / target_dev .20.5**。
- `open_tunnel(192.168.20.2, 22)` 发出与 KeyCmd **逐字节相同**的 CONNECT
  `57ab001006c0a814020016ac` → 设备回 `57ab009002ffe174`（connId=FF, **0xE1**）。
  **Opf_test 在当前固件下同样失败** → 排除 iOS 代码问题。

本机网络真值：`en11`（target 侧 ECM）ether **02:00:00:00:03:00**、inet
192.168.20.2、active；`ping 192.168.20.5`（设备 target 侧）→ ARP **(incomplete)**、
100% 丢包。**双向 ARP 均失败**。

机理：macOS 把 CDC-ECM 描述符 MAC 采纳为自己接口的 MAC。target 描述符
`MyTargetEcmMacInfo` = 02:00:00:00:03:00 → en11 MAC 即此值；而固件 ARP/GARP/ICMP/TCP
的 sender MAC `ECM_TARGET_DEV_MAC` / `g_dev_mac` 旧值**也是** 02:00:00:00:03:00。
macOS 丢弃源 MAC 等于自身接口 MAC 的帧（host 侧 ecm_bridge.c:88 注释早已警告此坑，
并用 ECM_DEV_MAC=…00:32 区别于描述符 …00:02 规避）→ 设备 ARP 请求被 Mac 丢弃
（不应答 → 0xE1），设备 ARP 应答也被 Mac 丢弃（ping incomplete）。

固件修复（Openterface_KM，镜像 host 侧；描述符保持 …03:00，peer 改 …03:32）：
- [x] `APP/ecm_bridge.c` `ECM_TARGET_DEV_MAC` → 02:00:00:00:03:32
- [x] `APP/ble_eth_protocol.c` `g_dev_mac` → 02:00:00:00:03:32
- [x] `APP/usbd_desc.c` `MyTargetEcmMacInfo` 注释改正（须与 peer **不同**）；描述符值不变
- 所有 ARP/GARP/DHCP/ICMP/TCP sender MAC 均引用上述两常量，无第三处遗漏

烧录后实证验证（2026-11-10，keymod-mlb / 11E6C99D，USB+BLE 同板）：
- [x] en11 重新枚举，MAC 仍 02:00:00:00:03:00（描述符），IP 192.168.20.2/24
- [x] `arp 192.168.20.5` 解析到 **02:00:00:00:03:32**（新 peer MAC，不再冲突）
- [x] `ping 192.168.20.5` 0% 丢包，~1ms（双向 ARP 恢复）
- [x] 探针 `open_tunnel(192.168.20.2,22)`：CONNECT_RESP `57ab009002000094`
      → connId=0 **status=0x00 SUCCESS**（修复前为 `ffe1` = 0xE1 超时）
- [x] 隧道回流目标机 SSH banner **`SSH-2.0-OpenSSH_10.2\r\n`**，随后干净 DISCONNECT
- [ ] KeyCmd iOS 真机 SSH 握手（CONNECT 拼帧已逐字节核对与 Opf_test 一致，
      网络层既通，预期可连；待用户在 App 内最终确认）
（注：探针会占用 BLE 连接，复测前先断开 KeyCmd/Opf_test GUI。）

## 14. 拓扑兼容性：仅 target ECM vs target + host 两个 ECM（2026-11-10）

需求：设备有时只接 target USB 口（host 口不接），有时 target + host 两个 ECM 同时接，
BLE SSL 隧道（走 target 侧）两种拓扑都必须能连。

固件侧核查结论（Openterface_KM，只读，无需改动）：
- host 侧（USBLIB，`ECM_Bridge_Init` @ ecm_bridge.c:2458）与 target 侧（USBFS，
  `ECM_Bridge_InitTarget` @ ecm_bridge.c:2503）由**两个独立 USB 控制器**初始化，
  main() 无条件都初始化，互不依赖。
- 链路标志独立：`g_host_ecm_data_if_active` / `g_target_ecm_data_if_active`
  （ecm_bridge.c:2749-2750）。target TX 只受 target 标志门控（poll_target_tx:2202），
  target RX（:2668）无 host 检查。host 缺席**不会**阻塞 target 侧。
- 帧路由：target 收帧先送 `BLE_Eth_HandleTargetFrame`（:2722）再复制到 host 队列
  `g_target_to_host`；host 不在只是该队列不再被 poll 排空，`queue_push` 非阻塞、
  溢出即丢（:1789），不会反压 BLE 隧道。
- 两个队列 `g_target_to_host` / `g_host_to_target`（:173,:176）深度各 2、各带独立
  generation 计数、无阻塞互斥；host TX 泵停摆不影响 target TX 泵或 BLE 处理。
- ARP/DHCP/IP 全在 target 侧：`send_arp_request`（ble_eth_protocol.c:1536）用
  `g_dev_mac=…03:32` / `g_dev_ip`，不依赖 host。
- self-MAC 修复（§13）纯 target 侧；`g_host_mac_learned` 无调用者（死状态），
  两侧无 MAC 学习交叉污染。

App 侧核查结论（KeyCmd iOS，无需改动）：
- SSH 默认主机恒取 `config.targetHostIP`（TerminalViewModel.swift:77-80、
  ConnectionDialog.swift:317），host 侧字段（hostIP/devIP）**只用于展示/编辑**，
  从不参与 SSH 连接决策 → 与拓扑无关。
- ECM GET 走 BLE 0x23，独立于 USB 链路，host 口不在也照常返回配置。

兼容性矩阵：
| 拓扑 | 物理接线 | SSH 隧道 | 依据 |
|------|----------|----------|------|
| A 仅 target | 只 target 口接目标机 | ✅ 可用（已实证） | §13 探针 Case A 成功 |
| B target+host（不同机器） | target→目标机，host→另一台 | ✅ 可用 | 两侧独立 + 桥接同子网 |
| B' target+host（同一台机） | 两 USB 口接**同一台**电脑 | ⚠️ 路由歧义 | 见下 |

关键约束（B' 需注意）：固件强制 host_ip/dev_ip/target_host_ip/target_dev_ip 全在
**同一子网**（ecm_ip_config.c:90-95 `validate_same_subnet` + 单一 subnet_mask）。
若两个 USB 口插到同一台电脑，该机将出现两个同网段（如 en13=.20.1、en11=.20.2，
均 192.168.20.0/24）接口，macOS 路由表有两条到 192.168.20.0/24 的路由，SSH 到 .20.2
可能从 en13 出而不走 target 隧道 → 表现为隧道连不上。这是桥接单子网设计的固有约束，
非 App/固件 bug。规避：host 与 target 接**不同**电脑；或同机时手动用 `route`/网络
服务顺序确保 .20.2 走 target 接口（不建议长期依赖）。

当前实测环境：本 Mac 仅存在 en11（target, MAC …03:00, 192.168.20.2/24），en13 host
接口不存在（只剩 stale "Openterface Host" 服务定义）→ 属 Case A，已实证 SSH 隧道通。