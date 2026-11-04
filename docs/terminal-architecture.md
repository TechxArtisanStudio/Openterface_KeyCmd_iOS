# Terminal Architecture — iOS Design

> **Version**: 2.0
> **Last updated**: 2026-11-03 (rewritten to match the shipped code; v1.0 described the
> 2026-06-20 plan, several parts of which were never built that way)
> **Ports**: Android `TerminalFragment` / `TerminalView` / `SshClient` / `CredentialManager`
> **Historical plans**: [archive/terminal-feature-plan.md](archive/terminal-feature-plan.md),
> [archive/implementation-summary.md](archive/implementation-summary.md)

This document describes the iOS terminal subsystem as it exists today: components, data
flow, rendering, key mappings, and credential storage.

Background survival depends on one build-settings detail worth repeating: the app declares
`UIBackgroundModes = [bluetooth-central]` in [KeyCmd-Info.plist](../KeyCmd-Info.plist),
which the app target references as `INFOPLIST_FILE` while keeping
`GENERATE_INFOPLIST_FILE = YES`, so Xcode merges it with the `INFOPLIST_KEY_*` build
settings. **`INFOPLIST_KEY_UIBackgroundModes` is silently dropped** by that mechanism (it
only maps a curated set of keys, and this one is not among them) — a background mode has
to come from a real plist. Verify with
`plutil -extract UIBackgroundModes xml1 <App>.app/Info.plist` after any change here.

---

## 1. Component Responsibilities

### Services Layer — `KeyCmd/Services/`

#### `TransportAdapter` (protocol) — `BleEth/TransportAdapter.swift`
Raw TCP byte streaming abstraction, ported from Android. Its real shape:

```swift
protocol TransportAdapter: AnyObject {
    var listener: TransportListener? { get set }
    func connect(host: String, port: Int, timeoutMs: Int)
    func send(data: Data)
    func disconnect()
    var isConnected: Bool { get }
}

protocol TransportListener: AnyObject {
    func onDataReceived(data: Data)
    func onDisconnected()
    func onError(message: String)
}
```

`connect` is fire-and-forget: callers poll `isConnected` afterwards (see
`TerminalViewModel.connect`). USB ECM is not implemented — only `BleEthTransport`
conforms today.

#### `BleEthTransport` (final class) — `BleEth/BleEthTransport.swift`
Implements `TransportAdapter` over BLE GATT using `BLEManager`. Owns the connection
state machine, TX fragmentation and RX reassembly. Additional API beyond the protocol:
`getInboundReader()` / `getOutboundWriter()`, which hand out a `QueuePipe` pair (see
below) for stream-style consumers. Frames are written
through `BLEManager.sendRawData(_:)`.

#### `FrameParser` (class) — `BleEth/FrameParser.swift`
Byte-level state machine for `[0x57][0xAB][ADDR][CMD][LEN][PAYLOAD][CHECKSUM]` frames.
See [ble-eth-protocol-spec.md](ble-eth-protocol-spec.md).

#### `DataReassembler` (struct) — `BleEth/DataReassembler.swift`
Reassembles fragmented DATA frames (3-byte fragment header: flags / seq / connId).
A bad fragment drops that fragment only and keeps reassembling; the spec's older
"discard the whole message" wording is corrected in the protocol doc.

#### `QueuePipe` (class) — `BleEth/QueuePipe.swift`
Thread-safe byte pipe built on `AsyncStream<Data>` with
`.bufferingNewest(limit, dropping: .never)` semantics — on overflow the **oldest**
buffered element is dropped silently. It replaces Java's
`PipedInputStream`/`PipedOutputStream`, which breaks when the writing thread exits
(the SSH handshake uses a transient connect thread).

#### `SSHClient` (class) — `SSH/SSHClient.swift`
Calls **libssh2 directly** through the `CSSH` module (`import CSSH`, supplied by the
local `../Libssh2Prebuild` package). NMSSH was planned and is **not** used.

- Session is put in non-blocking mode (`libssh2_session_set_blocking(…, 0)`); every
  step runs inside an EAGAIN retry loop driven by `libssh2_session_block_directions`
  plus `poll()` with a 1 s ceiling.
- Work is serialized on a private serial queue `ssh.client.queue`
  (`DispatchQueue`, `qos: .userInitiated`); `connect()` returns immediately.
- Channel output is drained by a reader loop on a global `userInitiated` queue. On
  `LIBSSH2_ERROR_EAGAIN` it **parks in `poll()`** on the bridge socket — `POLLIN` /
  `POLLOUT` as reported by `libssh2_session_block_directions`, 1 s ceiling — so an idle
  session costs no CPU and inbound data wakes the thread immediately instead of waiting up
  to a 10 ms tick. It calls no libssh2 function while parked.
- `libssh2Lock` serializes every libssh2 call that touches `session` / `channel`: each reader
  read, each `write()` attempt, `resizeTerminal()`, and the frees in `disconnect()`. Parking
  always happens **outside** the lock, so a contended lock is bounded by one non-blocking
  libssh2 call rather than by a poll timeout.
- `write()` and the reader re-resolve `channel`/`session` under the lock on every attempt
  instead of capturing the pointers up front, so a session closed mid-paste stops cleanly
  ("write stopped — session closed after N/M bytes") rather than writing through a freed
  channel. `write()` also parks on EAGAIN now, replacing its own 10 ms retry sleep.
- `disconnect()` clears `isConnected` before taking the lock, frees the channel and session
  inside it, then waits (≤1.5 s) for the reader to signal that it has exited.
  `bridge.stop()` closes the socketpair, so any parked `poll()` returns at once instead of
  delaying teardown.
- `performConnect()` runs unlocked. That is safe because the reader is only started at the end
  of it, and a reconnect cannot begin until the previous reader has exited (or the 1.5 s wait
  gave up and logged a warning — the one path where this guarantee weakens).
- Errors are the nested `SSHClient.SSHError` enum (`initializationFailed`,
  `sessionInitFailed`, `handshakeFailed(code:detail:)`, `authenticationFailed(code:)`,
  `channelOpenFailed(code:)`, `ptyRequestFailed`, `shellRequestFailed`,
  `execFailed(detail:)`, `commandFailed(exitCode:detail:)`) — there is no separate
  `SSHClientError.swift`.
- Output reaches callers through `onOutput: ((Data) -> Void)?` / `onError: ((String) -> Void)?`
  callbacks, not an `AsyncStream`.
- `SSHClient.execCommand(...)` exists separately for one-shot (non-interactive) commands.

#### `POSIXSocketBridge` (final class) — `SSH/SSHClient.swift`
The piece that lets libssh2, which insists on a file descriptor, talk to a BLE transport.
It creates a `socketpair(AF_UNIX, SOCK_STREAM)`, hands libssh2 one end, installs itself
as `transport.listener`, and pumps bytes both ways: socket → BLE in a detached task
capped at `DataReassembler.MAX_FRAG_DATA`, BLE → socket in `onDataReceived`.
`onDisconnected` tears it down.

> `SSH/LocalTCPProxy.swift` (a real loopback TCP server) is still in the tree but has
> **zero references** in app code. `POSIXSocketBridge` replaced it; treat the proxy as dead
> code until it is deleted.

#### `TerminalEmulator` (class) — `KeyCmd/View/Terminal/TerminalEmulator.swift`
Not a parser: it owns the `SSHClient` and acts as SwiftTerm's `TerminalViewDelegate`,
i.e. the bridge between "bytes on the wire" and "characters on screen".

- `attach(to:)` binds a SwiftTerm `TerminalView`, applies font, then derives the initial
  grid (`cols = max(width / 8.4, 80)`, `rows = max(height / 18, 24)`) and pushes it to the
  server via `sshClient.resizeTerminal`.
- `connect(profile:transport:bridge:)` sets credentials, starts the client and polls
  `sshClient.isConnected` (300 × 100 ms) before throwing.
- `clearScreen()` calls `getTerminal().resetToInitialState()`.
- Nested `ConnectionProfile` (host/port/username/password) and `ConnectionStatus`
  (`disconnected` / `connecting` / `connected` / `error(String)`).

#### `TerminalPrefs` (class, singleton) — `TerminalPrefs.swift`
`TerminalPrefs.shared`, UserDefaults-backed. `lastHost` / `lastPort` / `lastUsername`
do not exist — connection details live in credential profiles instead.

| Property | Default | UserDefaults key | Actually used? |
|---|---|---|---|
| `fontSize: CGFloat` | 14 when unset | `terminal_font_size` | yes (canvas + emulator) |
| `terminalRows: Int` | 24 | `terminal_rows` | no (read-only, no callers) |
| `terminalCols: Int` | 80 | `terminal_cols` | no |
| `scrollbackSize: Int` | 2000 | `terminal_scrollback` | no |
| `hasFontSizeOverride: Bool` | — | derived | yes |

### UI Layer — `KeyCmd/View/Terminal/`

| Component | Kind | Role |
|---|---|---|
| `TerminalContainerView` | `struct … : View` | Composes toolbar, canvas and bottom bar; owns the connection sheet and keyboard-height padding; seeds the default profile `onAppear` |
| `TerminalViewModel` | `class … : ObservableObject` | `@Published connectionStatus / terminalTitle / statusMessage`; the `connect(host:port:username:password:) async` orchestration; `send(data:)`, `send(text:)`, `sendSpecialKey(_:)`; nested `SpecialKey` enum |
| `TerminalCanvas` | `struct … : UIViewRepresentable` | Wraps SwiftTerm's UIKit `TerminalView`; `updateUIView` is intentionally empty (SwiftTerm repaints itself); `Coordinator` hosts the pinch gesture |
| `TerminalToolbar` | `struct … : View` | SF Symbols only: `keyboard` (toggle bottom bar), `plus.circle` / `xmark.circle`, status dot + caption |
| `TerminalBottomBar` | `struct … : View` | Special-key buttons (see [Section 5](#5-key-mapping)) plus a `Disconnect` text button while connected |
| `ConnectionDialog` | `struct … : View` | Connect sheet, with private `ProfileCard` / `TransportBadge` / `DeviceInfoSheet` and public `ProfileEditorSheet`, `TagSelectorView` |
| `CredentialProfile` | `struct … : Identifiable, Codable, Equatable` | `id/name/host/port/username/authType/targetOs/notes/tags/isActive/createdAt/updatedAt`; `AuthType` = `password` \| `sshKey` (`"ssh_key"`). **No password field** |
| `CredentialManager` | `class … , singleton` | Persistence + lookup (see [Section 9](#9-credential-management)) |
| `CredentialSettingsView` | `struct … : View` | Standalone profile list/editor, opened from the terminal sidebar gear in `ContentView` |

There is no `TerminalView`, `TerminalInputHandler` or `CredentialStore` type — those names
belong to the superseded plan.

---

## 2. Data Flow

### Connect sequence

```
ConnectionDialog.connectSelected()
    → CredentialManager.getPassword(for:)        (Keychain)
    → CredentialManager.setActiveProfileId(_:)
    → TerminalViewModel.connect(host:port:username:password:)
        → guard bleManager.connectedDevices not empty   else .error("BLE not connected")
        → BleEthTransport(bleManager:)
        → POSIXSocketBridge() ; bridge.start(transport:)   ← bridge before connect
        → transport.connect(host:port:timeoutMs: 30000)
        → poll transport.isConnected (50 × 100 ms)
        → emulator.connect(profile:transport:bridge:)
            → sshClient.setCredentials(...)
            → sshClient.connect(transport:bridge:)
            → poll sshClient.isConnected (300 × 100 ms)
```

### SSH output → screen

```
libssh2_channel_read_ex (SSHClient output reader loop)
    → SSHClient.onOutput(Data)
    → TerminalEmulator.feedTerminal(data:)
    → SwiftTerm TerminalView.feed(byteArray:)     (ANSI/VT parsing + layout)
    → SwiftTerm draws its own UIKit view          (no SwiftUI Canvas involved)
```

### Typed / pressed input → SSH

```
SwiftTerm TerminalView keyboard (UIKeyInput)  or  TerminalBottomBar button
    → TerminalViewDelegate.send(source:data:)     → TerminalEmulator
    → or TerminalViewModel.sendSpecialKey(_:)
    → SSHClient.write(data:)                       (sshQueue)
    → POSIXSocketBridge  (socketpair → BLE-Eth frames)
    → BleEthTransport.send(data:) → fragmentation
    → BLEManager.sendRawData(_:) → FFF2, .withResponse, 128-byte chunks
```

### BLE-Eth inbound → SSH

```
FFF1 notification → BLEManager.peripheral(_:didUpdateValueFor:)
    → BLEManager.rawDataSubject.send(data)        (published unconditionally)
    → BleEthTransport subscription
    → FrameParser → DataReassembler
    → transport.listener = POSIXSocketBridge.onDataReceived
    → Darwin.write(bridgeFd) → libssh2 reads the socket
```

---

## 3. Integration with BLEManager

`KeyCmd/Managers/BLEManager.swift` contributes two things to the terminal:

1. **`sendRawData(_:)`** — writes to FFF2 with `.withResponse` for **every** frame
   (control and data alike). The device firmware needs the BLE-level ACK before it
   forwards payload to TCP; `.withoutResponse` loses data silently. Payload larger than
   `BLEConstants.safeChunkSize` (128 bytes) is chunked with a 10 ms inter-chunk delay.
   A leftover debug log still prints `writeType=…withoutResponse` for non-control
   frames; the actual write type never varies.
2. **`rawDataSubject: PassthroughSubject<Data, Never>`** — every `didUpdateValueFor`
   notification on **FFF1** is forwarded to subscribers as-is.

There is **no `isTerminalMode` flag** and no HID-report parsing on the notification
path: routing is by characteristic UUID, and the mode is whatever the device firmware
is in. When the device is in HID mode nothing subscribes to `rawDataSubject`, so the
data is dropped; the app does not detect or display the device's current mode.

---

## 4. Terminal Emulation

All emulation is delegated to **SwiftTerm** (resolved from the local `../SwiftTerm`
package). The app implements no escape-sequence state machine.

| Feature | Support |
|---|---|
| Cursor control | Absolute/relative positioning, save/restore, visibility (DEC mode 25) |
| Erase operations | Line (to cursor / from cursor / entire), screen (same modes) |
| Scroll regions | Custom top/bottom bounds, scrollback buffer |
| Attributes (SGR) | Bold, italic, underline, blink, inverse |
| Colors | 8 standard, 16 with bright, 256-color, 24-bit true color |
| Alternate screen | DEC modes 47, 1047, 1049 |
| Application cursor keys | DECCKM (SS3 sequences) |
| Device status reports | CPR, DA1 |
| UTF-8 | Multi-byte decoding |

Dimensions are decided by SwiftTerm from the view's frame, then pushed to the server:
the pty is requested at a fixed 80×24 `xterm-256color` during setup
(`libssh2_channel_request_pty_ex`), and every later `sizeChanged` delegate callback
re-sizes it through `libssh2_channel_request_pty_size_ex`. `TerminalPrefs.terminalCols`
and `terminalRows` are not part of this path.

---

## 5. Key Mapping

Standard typing, modifiers and the ordinary function keys come from **SwiftTerm's own
keyboard handling** — `TerminalView` is a `UIScrollView` conforming to `UIKeyInput` /
`UITextInputTraits` and owns `inputView` and first-responder state. KeyCmd adds no
`UITextView` of its own.

The bottom bar (`TerminalBottomBar` → `TerminalViewModel.SpecialKey`) sends exactly
these bytes:

| Button | Bytes | Note |
|---|---|---|
| `Ctrl` | `0x03` | **sends Ctrl+C immediately — there is no Ctrl latch/modifier state anywhere** |
| `Esc` | `0x1B` | |
| `Tab` | `0x09` | |
| `←` `↑` `↓` `→` | `0x1B 5B 44 / 41 / 42 / 43` | `\e[D`, `\e[A`, `\e[B`, `\e[C` (normal mode only; DECCKM is handled by SwiftTerm) |
| `Home` | `0x1B 5B 48` | |
| `End` | `0x1B 5B 46` | |
| `PgUp` / `PgDn` | `0x1B 5B 35 7E` / `0x1B 5B 36 7E` | |
| `Enter` | `0x0D` | |
| `Backspace` | `0x7F` (DEL) | |
| `Delete` | `0x08` | sent as BS-DEL, not `\e[3~` |
| `Ctrl+D` / `Ctrl+Z` | `0x04` / `0x1A` | |

Not wired to any button (SwiftTerm emits them only if the hardware/soft keyboard
produces them): Insert `\e[2~`, F1–F12, and the full `Ctrl+A–Z` range.

---

## 6. UI Layout

```
┌─────────────────────────────────────────┐
│ TerminalToolbar  ⌨︎   ⊕/⊗   ● status     │  SF Symbols + caption, no text buttons
├─────────────────────────────────────────┤
│ TerminalCanvas                            │
│   SwiftTerm TerminalView (UIScrollView)   │  flexible
│   pinch-to-zoom gesture on top            │
│   [connection overlay while disconnected] │
├─────────────────────────────────────────┤
│ TerminalBottomBar (only when toggled on)  │
│  Ctrl Esc Tab ← ↑ ↓ → …  [Disconnect]    │
└─────────────────────────────────────────┘
```

`TerminalContainerView` listens for `keyboardWillShow`/`keyboardWillHide` and pads the
bottom bar above the soft keyboard.

### Connection sheet

`ConnectionDialog` is a profile-first sheet: saved profiles (with tags and an
active-profile marker), a `ProfileEditorSheet` for create/edit, a device-info sheet,
and a transport badge. The transport is BLE-Eth only; the "USB ECM disabled" control
from the original plan was not built. Connect reads the password from the Keychain at
tap time.

---

## 7. Rendering Strategy

**SwiftTerm renders, we do not.** `TerminalCanvas` is a `UIViewRepresentable` whose
`updateUIView` is empty on purpose — feeding bytes into `TerminalView` is enough. The
earlier "SwiftUI `Canvas` character-grid renderer" design was abandoned.

- **Font**: `"Menlo"`, falling back to `UIFont.monospacedSystemFont`. No font is bundled:
  there is no `KeyCmd/Resources/Fonts`, no `UIAppFonts`, and the project generates its
  Info.plist (`GENERATE_INFOPLIST_FILE = YES`), so the JetBrains Mono plan item never landed.
- **Size**: default 14 pt; `UIPinchGestureRecognizer` in the canvas Coordinator clamps to
  **10–32 pt** (not 6–48) and persists on `.ended` / `.cancelled`.
- **Cursor, attributes, colors, scrollback**: all SwiftTerm behavior, including blink.

---

## 8. SSH Client Configuration

libssh2 session preferences set in `SSHClient.configureSessionPreferences`:

| Setting | Value |
|---|---|
| Timeout | 30 000 ms |
| KEX | `curve25519-sha256`, `diffie-hellman-group14-sha256`, `diffie-hellman-group14-sha1` |
| Host key | `ssh-ed25519`, `ecdsa-sha2-nistp256`, `ssh-rsa` |
| Cipher (both directions) | `aes256-gcm@openssh.com`, `aes128-gcm@openssh.com`, `aes256-ctr`, `aes192-ctr`, `aes128-ctr` |
| MAC (both directions) | `hmac-sha2-256-etm@openssh.com`, `hmac-sha2-512-etm@openssh.com`, `hmac-sha2-256` |
| Compression | `none`, `zlib@openssh.com` |
| Auth | password (`libssh2_userauth_password_ex`) |
| PTY | `xterm-256color`, requested at 80×24, resized later |
| Channel | `session`, 2 MB window, 32768 packet |

Blocking model: none — `libssh2_session_set_blocking(…, 0)` plus EAGAIN/`poll()` retries,
as described in [Section 1](#services-layer--keycmdservices). `disconnect()` deliberately
skips `libssh2_exit()` because other sessions could share the process-wide library state.

---

## 9. Credential Management

Split storage, implemented by `CredentialManager` (`View/Terminal/CredentialManager.swift`):

- **Metadata** — `[CredentialProfile]` JSON in `UserDefaults` under `credential_profiles`;
  the active profile id under `credential_active_id`. Profiles carry host, port, username,
  `authType`, target OS, notes, tags and `isActive`.
- **Secrets** — never in UserDefaults. Passwords go to the Keychain via `KeychainHelper`
  (`kSecClassGenericPassword`, service `com.openterface.keycmd`, account
  `credential_pw_<profileId>`).
- `ensureDefaultKeyCmdProfile()` seeds one profile on first appearance: name
  "KeyCmd default", host `192.168.12.1`, port 22, user `root`.
- `AuthType.sshKey` exists in the model, but the Keychain stores only passwords today —
  key authentication is not implemented in `SSHClient`.

Presented from two places: the in-terminal `ConnectionDialog` sheet, and
`CredentialSettingsView` behind the terminal sidebar gear.

---

## 10. File Inventory (actual)

```
KeyCmd/Services/
├── BleEth/
│   ├── TransportAdapter.swift      (TransportAdapter + TransportListener protocols)
│   ├── BleEthTransport.swift       (BLE-Eth wire protocol, fragmentation, state machine)
│   ├── FrameParser.swift           (frame state machine)
│   ├── DataReassembler.swift       (fragment reassembly)
│   └── QueuePipe.swift             (AsyncStream byte pipe)
└── SSH/
    ├── SSHClient.swift             (libssh2 via CSSH + SSHError + POSIXSocketBridge)
    └── LocalTCPProxy.swift         (UNUSED — superseded by POSIXSocketBridge)

KeyCmd/View/Terminal/
├── TerminalContainerView.swift     (composition root)
├── TerminalViewModel.swift         (state machine + connect orchestration)
├── TerminalCanvas.swift            (UIViewRepresentable over SwiftTerm TerminalView)
├── TerminalEmulator.swift          (SSHClient + TerminalViewDelegate bridge)
├── TerminalToolbar.swift           (SF Symbols controls)
├── TerminalBottomBar.swift         (special-key strip)
├── TerminalPrefs.swift             (UserDefaults singleton)
├── ConnectionDialog.swift          (connect sheet + profile editor + tags + device info)
├── CredentialProfile.swift         (Codable model + AuthType)
├── CredentialManager.swift         (UserDefaults metadata + Keychain secrets)
└── CredentialSettingsView.swift    (standalone profile management screen)
```

No `Resources/Fonts/` and no `Models/CredentialProfile.swift`.

App-level configuration: [KeyCmd-Info.plist](../KeyCmd-Info.plist) at the repository root
(holds `UIBackgroundModes`; referenced by the app target only, so test targets keep
generating their plists from build settings alone).

Entry point: `ViewManager.ViewType.terminal` ("Terminal"), listed in the sidebar for both
Basic and Pro modes and switched in `ContentView`; a single `TerminalViewModel` is created
there for the app's lifetime. The first-run `LaunchPanelView` does **not** offer Terminal.

---

## 11. Testing

Automated (see `KeyCmdTests/`):

- `FrameParserTests` — addr/cmd/len/payload/checksum decoding.
- `DataReassemblerTests` — in-order reassembly; a bad fragment drops that fragment.
- `QueuePipeTests` — pipe semantics under load.
- `BleEthTransportTests` — includes the "all writes use `.withResponse`" rule from
  [Section 7 of the protocol spec](ble-eth-protocol-spec.md).
- `TerminalViewModelTests` — connect guards and state transitions.

Every test file must `@testable import KeyCmd`. Four of them still named `KeyMod` — a module
this project has not had since the rename `4a43311` (2026-06-03) — which failed the entire
unit-test target from `c2875b0` (2026-06-29, when those files were added) until 2026-11-03.
No build setting aliases the old name, so a new test file written against `KeyMod` breaks the
target the same way.

Manual, against real hardware (BLE cannot run on the Simulator):

1. Pair with the Openterface device, open Terminal, pick or create a profile, connect.
2. Verify handshake, prompt rendering, typing, color output (`ls --color`), arrow-key
   history, and that the `Ctrl` button interrupts with Ctrl+C.
3. Resize by rotating / pinch-zooming and confirm the remote adapts (`stty size`, `tput cols`).
4. Disconnect and reconnect without re-pairing BLE.

Performance: SwiftTerm drives its own redraw; the practical check is throughput during
`cat` on a large file plus responsiveness of the bottom bar.

---

## 12. Known Gaps

| Gap | Evidence | Impact |
|---|---|---|
| `Ctrl` button is hardcoded Ctrl+C | `TerminalViewModel.SpecialKey` | No Ctrl+letter chords from the UI |
| `LocalTCPProxy.swift` unreferenced | zero call sites | Dead code; confuses readers of the older docs |
| SSH key auth declared but unimplemented | `AuthType.sshKey` in model, password-only in `SSHClient` | Key-based hosts unreachable |
| `TerminalPrefs.terminalCols` / `terminalRows` / `scrollbackSize` unused | no external callers | Settings would silently do nothing if wired |
| Device HID-vs-tunnel mode not detected | `BLEManager` routes by characteristic only | User cannot tell why a connect fails |
| Terminal absent from the launch panel | `LaunchPanelView` mode list | First-run users must know the sidebar exists |
