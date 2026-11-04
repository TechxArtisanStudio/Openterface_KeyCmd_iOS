# Terminal Feature — iOS Implementation Plan

> **ARCHIVED 2026-11-03 — plan of record, now superseded.** Phases 3-5 marked "In
> progress" / "Not started" below are all shipped: the terminal lives in
> `KeyCmd/View/Terminal/` and is reachable from the mode sidebar
> (`KeyCmd/Managers/ViewManager.swift`, `KeyCmd/View/ContentView.swift`), though it is
> still absent from the first-run launch panel. Library choices also changed: no
> `NMSSH` -- `SSHClient` is a direct `import CSSH` (a product of the local
> `../Libssh2Prebuild` package) plus `import Network`. Several planned names never
> landed: `Services/Terminal/`, `Views/Terminal/`, `SSHClientError.swift`,
> `TerminalInputHandler.swift`, `CredentialStore.swift`, `Views/MainView.swift` and
> `KeyModApp.swift` do not exist; the real equivalents are `KeyCmd/View/Terminal/`,
> the nested `SSHClient.SSHError`, inline key mapping in the bottom bar, and
> `CredentialManager` + `CredentialProfile`.
>
> One planned item was still open when this banner was written, and has since been fixed:
> **`UIBackgroundModes = [bluetooth-central]`** is now declared in
> [`KeyCmd-Info.plist`](../../KeyCmd-Info.plist), so a BLE-backed session can survive
> backgrounding. (Note for whoever revisits it: setting
> `INFOPLIST_KEY_UIBackgroundModes` as a build setting does nothing — Xcode silently
> drops that key.)
>
> See [docs/README.md](../README.md) for the current documentation set.

## Overview

Port the Android terminal feature to iOS, enabling SSH connectivity to remote systems over the BLE-Eth transport (custom frame protocol tunneled over BLE GATT). Includes a full VT100/ANSI terminal emulator with color support.

## Status

- **Phase 1**: BLE-Eth Transport — ✅ Complete
- **Phase 2**: SSH Client — ✅ Complete (libssh2 via local SPM + LocalTCPProxy)
- **Phase 3**: Terminal Emulator — In progress
- **Phase 4**: SwiftUI Terminal UI — Not started
- **Phase 5**: Navigation & Integration — Not started

## iOS-Specific Constraints

- **No USB ECM transport in v1**: iOS does not expose raw USB serial without MFi or `ExternalAccessory`. Ship with BLE-Eth only. USB ECM can be added later via `NETransparentProxy` or MFi if needed.
- **BLE throughput**: iOS CoreBluetooth MTU ~185–512 bytes after negotiation. The BLE-Eth fragmentation protocol (246-byte fragments, 5ms inter-fragment delay) ports directly.
- **Background execution**: SSH sessions need `bluetooth-central` + `background-processing` background modes.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│          TerminalView (SwiftUI)                      │
│  - Terminal screen (SwiftUI Canvas)                  │
│  - Toolbar: status, connect button                   │
│  - Bottom bar: Ctrl | Esc | Tab                      │
│  - Pinch-to-zoom font size                           │
└─────────────────────┬────────────────────────────────┘
                      │
             ┌────────▼────────┐
             │ TerminalViewModel│  (@MainActor ObservableObject)
             │  - connection state
             │  - credential profile selection
             │  - input routing
             └────────┬────────┘
                      │
             ┌────────▼────────┐
             │   SSHClient      │  (NMSSH wrapper)
             │  SSH-2.0 shell   │
             └────────┬────────┘
                      │
          ┌───────────▼────────────┐
          │ TransportAdapter       │ (protocol)
          └───────────┬────────────┘
                      │
           ┌──────────▼──────────┐
           │  BleEthTransport    │
           │  (uses BLEManager)  │
           └──────────┬──────────┘
                      │
           ┌──────────▼──────────┐
           │ BLEManager (existing)│
           │  FFF2 characteristic │
           └─────────────────────┘
```

## Implementation Phases

### Phase 1: BLE-Eth Transport

Port the BLE-Eth frame protocol from Java to Swift.

| File | Purpose |
|------|---------|
| `Services/BleEth/TransportAdapter.swift` | Protocol: `connect()`, `send(_:)`, `disconnect()`, `isConnected`, `setListener(_:)` |
| `Services/BleEth/FrameParser.swift` | State machine for `[0x57][0xAB][ADDR][CMD][LEN][PAYLOAD][CHECKSUM]` frames |
| `Services/BleEth/DataReassembler.swift` | Reassemble fragmented DATA frames (3-byte frag header: flags/seq/connId) |
| `Services/BleEth/BleEthTransport.swift` | Implements `TransportAdapter`, sends/receives via `BLEManager.shared` |
| `Services/BleEth/QueuePipe.swift` | Thread-safe byte pipe using `AsyncStream` |

**Integration**: Extend `BLEManager` with `sendRawData(_: Data)` for raw BLE writes and a `rawDataSubject: PassthroughSubject<Data, Never>` for incoming raw data bypassing HID parsing.

### Phase 2: SSH Client

| File | Purpose |
|------|---------|
| `Services/SSH/SSHClient.swift` | Wraps NMSSH: `connect`, `authenticate`, `openShell`, `send`, output via `AsyncStream` |
| `Services/SSH/SSHClientError.swift` | Error enum for connection, auth, channel failures |

**Approach**: Run a local TCP proxy on `127.0.0.1:<ephemeral>` bridged to `BleEthTransport` (like Android's `BleSshProxy`), then have NMSSH connect to it. Simpler than replacing NMSSH's internal sockets.

### Phase 3: Terminal Emulator

| File | Purpose |
|------|---------|
| `Services/Terminal/TerminalEmulator.swift` | Wrapper around `SwiftTerm.Terminal` |
| `Services/Terminal/TerminalPrefs.swift` | UserDefaults: font size, rows/cols, scrollback, last connection |

**Library**: Use [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT, pure Swift) — avoids porting ~2000 LOC of escape-sequence state machines.

### Phase 4: SwiftUI Terminal UI

| File | Purpose |
|------|---------|
| `Views/Terminal/TerminalView.swift` | Main view — canvas + toolbar + bottom bar |
| `Views/Terminal/TerminalCanvas.swift` | `Canvas`-based renderer for character grid |
| `Views/Terminal/TerminalViewModel.swift` | Connection state machine |
| `Views/Terminal/ConnectionDialog.swift` | SSH connect sheet |
| `Views/Terminal/TerminalInputHandler.swift` | Key → escape sequence mapping |
| `Views/Terminal/CredentialStore.swift` | Keychain-backed credential profiles |

**Rendering**: SwiftUI `Canvas` for the character grid. Font: bundle `JetBrainsMono` or `NotoSansMono`. Pinch-to-zoom font size 6–48pt.

### Phase 5: Navigation & Integration

| File | Change |
|------|--------|
| `Views/MainView.swift` | Add "Terminal" entry to navigation |
| `KeyModApp.swift` | Register `TerminalView` |
| `Info.plist` | Add `UIBackgroundModes: bluetooth-central`, `UIAppFonts` |
| Project | Add SPM deps: `NMSSH`, `SwiftTerm` |

## SPM Dependencies

- **NMSSH** — SSH-2.0 client (Obj-C, mature, maps 1:1 to Android JSch usage)
- **SwiftTerm** — Terminal emulator (pure Swift, MIT license)

## Verification

1. **Unit tests**: `FrameParser`, `DataReassembler`, `TerminalInputHandler`
2. **Integration test**: BLE pair → Terminal tab → BLE-Eth connect → SSH shell → verify rendering, colors, key input, Ctrl+C, pinch-to-zoom
3. **Performance**: 30+ fps during rapid terminal updates (e.g., `cat` large file)
4. **Background**: Session survives background/foreground cycle

## Phased Rollout

- **v1 (this plan)**: BLE-Eth + SSH + terminal UI
- **v2**: USB ECM via `NETransparentProxy` or MFi
- **v3**: SFTP file browser over same SSH session

## Reference Docs

- [../ble-eth-protocol-spec.md](../ble-eth-protocol-spec.md) — Wire protocol specification
- [../terminal-architecture.md](../terminal-architecture.md) — Terminal subsystem design
