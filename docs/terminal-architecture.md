# Terminal Architecture — iOS Design

> **Version**: 1.0
> **Last updated**: 2026-06-20
> **Source**: Ported from Android `TerminalFragment.java`, `TerminalView.java`, `TerminalSession.java`, `AnsiEscapeParser.java`, `SshClient.java`, `CredentialManager.java`

This document defines the iOS terminal subsystem architecture — components, data flow, rendering strategy, and key mappings.

---

## 1. Component Responsibilities

### Services Layer

#### `TransportAdapter` (protocol)
Abstract interface for raw byte streaming. Defines:
- `connect(host:port:timeoutMs:)`
- `send(_ data: Data)`
- `disconnect()`
- `isConnected: Bool`
- `setListener(_ listener: TransportListener)`

#### `BleEthTransport` (class)
Implements `TransportAdapter` for BLE-Eth protocol. Uses `BLEManager.shared` to send/receive frames. Manages connection state machine, fragmentation, and reassembly. Exposes `InputStream`/`OutputStream` for SSH client integration (via local TCP proxy bridged to BLE-Eth).

#### `QueuePipe` (class)
Thread-safe byte pipe using `AsyncStream<Data>`. Replaces Java's `PipedInputStream/PipedOutputStream` which fails when the writing thread exits (SSH handshake uses a transient connect thread).

#### `SSHClient` (class)
Wraps NMSSH library. Provides:
- `connect(host:port:)` — establishes TCP connection (via local proxy → BleEthTransport)
- `authenticate(username:password:)` — SSH auth
- `openShell()` — opens shell channel with `xterm-256color` pty
- `send(_ data: Data)` — writes to shell stdin
- `output: AsyncStream<Data>` — reads from shell stdout

#### `TerminalEmulator` (class)
Wrapper around `SwiftTerm.Terminal`. Bridges SSH output to terminal input, exposes screen buffer state for rendering. Delegates all VT100/ANSI parsing to SwiftTerm.

#### `TerminalPrefs` (struct)
UserDefaults-backed preferences:
- `fontSize: Double` (default 12.0, range 6.0–48.0)
- `columns: Int` (default 80)
- `rows: Int` (default 24)
- `scrollbackSize: Int` (default 2000)
- `lastHost: String?`, `lastPort: Int?`, `lastUsername: String?`

### UI Layer

#### `TerminalViewModel` (@MainActor ObservableObject)
Manages connection state machine:
- `disconnected` → `connecting` → `connected` → `disconnected`
- Publishes state changes via `@Published var connectionState`
- Handles credential profile selection, transport selection
- Routes key input to SSH client

#### `TerminalView` (SwiftUI View)
Main view — composes toolbar, terminal canvas, bottom bar. Manages connection dialog presentation.

#### `TerminalCanvas` (SwiftUI View)
`Canvas`-based renderer for the character grid. Draws characters with per-cell colors and attributes (bold, italic, underline, inverse). Redraws on screen buffer updates.

#### `ConnectionDialog` (SwiftUI View)
Sheet/overlay for SSH connection:
- Profile picker (saved credential profiles)
- Host/port/username/password fields
- Transport toggle (BLE-Eth only in v1)

#### `TerminalInputHandler` (struct)
Maps SwiftUI keyboard events + bottom bar buttons to terminal input sequences (see Section 5).

#### `CredentialStore` (class)
Keychain-backed credential profiles. Stores `CredentialProfile` structs with id/name/host/port/username/password.

---

## 2. Data Flow

### SSH Output → Screen Rendering

```
SSHClient.output (AsyncStream<Data>)
    │
    ▼
TerminalEmulator.feed(data:)
    │
    ▼
SwiftTerm.Terminal (parses ANSI/VT100, updates screen buffer)
    │
    ▼
TerminalEmulator.getScreenBuffer() → [CharacterCell]
    │
    ▼
TerminalCanvas (SwiftUI Canvas) — redraws character grid
```

### Key Input → SSH Input

```
SwiftUI .onKeyPress / bottom bar buttons
    │
    ▼
TerminalInputHandler.map(key:) → Data (escape sequence bytes)
    │
    ▼
TerminalViewModel.sendInput(data:)
    │
    ▼
SSHClient.send(data:)
    │
    ▼
BleEthTransport.send(data:)
    │
    ▼
BLEManager.sendRawData(data:) → FFF2 characteristic
```

### BLE-Eth Receive → SSH Input

```
BLE notification (FFF1 or data characteristic)
    │
    ▼
BLEManager.rawDataSubject.publish(data)
    │
    ▼
BleEthTransport.handleIncomingData(data:)
    │
    ▼
FrameParser.parse(data:) → ParsedFrame
    │
    ▼
DataReassembler.feed(frame:) → ReassembledData
    │
    ▼
Local TCP proxy → NMSSH reads from socket
```

---

## 3. Integration with Existing BLEManager

### Current BLEManager

The existing `BLEManager` (singleton, `ObservableObject`) handles:
- BLE scanning, connection, service/characteristic discovery
- HID keyboard/mouse data via `sendTouchData(data: Data)` — writes to FFF2 `.withoutResponse`
- Parses incoming BLE notifications as HID reports

### Extensions Needed

Add two new capabilities:

1. **Raw data write** (mirrors `sendTouchData` but for arbitrary bytes):
```swift
// NOTE: Must use .withResponse — device firmware requires BLE-level ACK
// before processing and forwarding data to TCP. .withoutResponse causes
// silent data loss (device ACKs at BLE-Eth level but drops payload).
func sendRawData(_ data: Data) {
    guard let peripheral = connectedPeripheral,
          let characteristic = fff2Characteristic else { return }
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
}
```

2. **Raw data receive** (bypasses HID parsing):
```swift
let rawDataSubject = PassthroughSubject<Data, Never>()

// In didUpdateValueFor characteristic delegate:
if isTerminalMode {
    rawDataSubject.send(data)
} else {
    parseHIDReport(data)  // existing behavior
}
```

**Mode switching**: The Openterface device operates in either HID mode (keyboard/mouse) or Terminal mode (BLE-Eth tunnel). The mode is determined by the device firmware based on user selection on the device itself. The iOS app should detect which mode is active (via a characteristic read or device notification) and route incoming data accordingly.

---

## 4. Terminal Emulation Features

### VT100/ANSI Support (via SwiftTerm)

SwiftTerm provides full VT100/VT220/xterm emulation:

| Feature | Support |
|---------|---------|
| Cursor control | Absolute/relative positioning, save/restore, visibility (DEC mode 25) |
| Erase operations | Line (to cursor, from cursor, entire), screen (same modes) |
| Scroll regions | Custom top/bottom bounds, scrollback buffer |
| Attributes (SGR) | Bold, italic, underline, blink, inverse |
| Colors | 8 standard, 16 with bright, 256-color, 24-bit true color |
| Alternate screen buffer | DEC modes 47, 1047, 1049 |
| Application cursor keys | DECCKM mode (SS3 sequences for arrows) |
| Device status reports | CPR (cursor position), DA1 (device attributes) |
| UTF-8 | Full multi-byte decoding |

### Screen Buffer Structure

SwiftTerm manages:
- `screen: [[CharacterCell]]` — visible screen (char + attributes at each cell)
- `scrollback: [[CharacterCell]]` — scrollback history (limited to `scrollbackSize`)
- `altScreen: [[CharacterCell]]` — alternate screen buffer (for full-screen apps)

Each `CharacterCell` contains:
- `character: Character`
- `fgColor: TerminalColor`
- `bgColor: TerminalColor`
- `bold: Bool`
- `italic: Bool`
- `underline: Bool`
- `inverse: Bool`
- `blink: Bool`

### Terminal Dimensions

- Default: 80 columns × 24 rows
- Scrollback: 2000 lines (configurable)
- These are sent to the remote via SSH pty configuration (`xterm-256color`, 80×24)

---

## 5. Key Mapping Table

Every special key mapped to escape sequences:

| Key | Normal Mode | Application Mode (DECCKM) |
|-----|-------------|---------------------------|
| Enter | `\r` (0x0D) | same |
| Tab | `\t` (0x09) | same |
| Escape | `0x1B` | same |
| Backspace | `0x7F` (DEL) | same |
| Delete | `\e[3~` | — |
| Arrow Up | `\e[A` | `\eOA` |
| Arrow Down | `\e[B` | `\eOB` |
| Arrow Left | `\e[D` | `\eOD` |
| Arrow Right | `\e[C` | `\eOC` |
| Home | `\e[H` | — |
| End | `\e[F` | — |
| Insert | `\e[2~` | — |
| Page Up | `\e[5~` | — |
| Page Down | `\e[6~` | — |
| F1 | `\eOP` | — |
| F2 | `\eOQ` | — |
| F3 | `\eOR` | — |
| F4 | `\eOS` | — |
| F5 | `\e[15~` | — |
| F6 | `\e[17~` | — |
| F7 | `\e[18~` | — |
| F8 | `\e[19~` | — |
| F9 | `\e[20~` | — |
| F10 | `\e[21~` | — |
| F11 | `\e[23~` | — |
| F12 | `\e[24~` | — |
| Ctrl+A–Z | `0x01`–`0x1A` | same |

**Bottom bar special key buttons**:
- `Esc` → sends `0x1B`
- `Tab` → sends `0x09`
- `Ctrl` → opens keyboard (user types next character with Ctrl held)

---

## 6. UI Layout

```
┌─────────────────────────────────────────┐
│ Toolbar: Status + Connect Button        │  44pt
├─────────────────────────────────────────┤
│                                         │
│  TerminalCanvas (SwiftUI Canvas)        │  flexible
│  - Screen buffer rendering              │
│  - Touch input + pinch-to-zoom          │
│                                         │
│  [Connection Overlay when disconnected] │
│                                         │
├─────────────────────────────────────────┤
│ Bottom Bar: Ctrl | Esc | Tab            │  36pt
└─────────────────────────────────────────┘
```

### Connection Dialog

```
┌─────────────────────────────────────────┐
│ SSH Connection                          │
├─────────────────────────────────────────┤
│ Profile: [dropdown ▼]                   │
│                                         │
│ Transport:                              │
│   ○ BLE-Eth                             │
│   ○ USB ECM (disabled in v1)            │
│                                         │
│ Host: [192.168.1.5        ]             │
│ Port: [22                 ]             │
│ Username: [root           ]             │
│ Password: [••••••••       ]             │
│                                         │
│ [Cancel]          [Connect]             │
└─────────────────────────────────────────┘
```

### IME Handling

When soft keyboard is visible, the bottom bar auto-adjusts above the keyboard using SwiftUI's `.safeAreaInset(edge: .bottom)` or `GeometryReader` to detect keyboard height.

---

## 7. Rendering Strategy

### SwiftUI Canvas

Use `Canvas` view for the character grid:
- Redraws full screen on each buffer update
- For 80×24 = 1920 cells at 16pt font, `Canvas` can handle 60fps
- If performance is an issue, fall back to `UIViewRepresentable` wrapping a `CATextLayer` grid or `Metal`-backed view

### Font

- **Primary**: Bundle `JetBrainsMono-Regular.ttf` (or `NotoSansMono-Regular.ttf`)
- **Fallback**: System monospace (`UIFont.monospacedSystemFont`)
- Add to `Info.plist` under `UIAppFonts`: `JetBrainsMono-Regular.ttf`

### Font Size & Pinch-to-Zoom

- Range: 6.0–48.0 pt
- Default: 12.0 pt
- `MagnificationGesture` on `TerminalCanvas` scales font size
- Persist to `TerminalPrefs.fontSize`

### Character Rendering

For each cell in the screen buffer:
1. Compute `x = col * charWidth`, `y = row * lineHeight`
2. Resolve `inverse` (swap fg↔bg)
3. If `bg != defaultBg`: draw filled rect at (x, y, charWidth, lineHeight)
4. If `ch != 0` and `ch != ' '`: draw character with attributes
   - `bold` → `text.font = .bold()`
   - `italic` → apply italic transform
   - `underline` → draw underline
5. Draw cursor (blinking block, 500ms interval, respects DEC mode 25)

### Cursor Blink

- Interval: 500 ms
- Toggle `cursorVisible` boolean
- Only blink if `terminal.isCursorVisible()` returns true (DEC mode 25)

---

## 8. SSH Client Configuration

### NMSSH Settings (matching Android JSch)

| Setting | Value |
|---------|-------|
| KEX | `curve25519-sha256` |
| Host key | `ssh-ed25519,rsa-sha2-512,rsa-sha2-256` |
| Cipher | `aes128-ctr` |
| MAC | `hmac-sha2-256` |
| Compression | none |
| Auth | `password,keyboard-interactive` |
| Handshake timeout | 20s |
| Terminal type | `xterm-256color` |
| Terminal dimensions | 80 cols × 24 rows |

### Local TCP Proxy

To bridge NMSSH (which expects a TCP socket) to `BleEthTransport` (which provides raw byte streams):

1. Start a local TCP server on `127.0.0.1:<ephemeral port>`
2. When NMSSH connects, bridge the TCP socket to `BleEthTransport`
3. TCP writes → `BleEthTransport.send(data:)`
4. BLE-Eth received data → TCP socket output stream

This is the same approach as Android's `BleSshProxy`. Simpler than replacing NMSSH's internal socket layer.

---

## 9. Credential Management

### Keychain Storage

Use iOS Keychain (via `Security.framework` or a wrapper like `KeychainAccess`) to store SSH credentials:

```swift
struct CredentialProfile: Codable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String
    var createdAt: Date
    var updatedAt: Date
}
```

### Profile Picker

The connection dialog shows a dropdown of saved profiles. Selecting a profile auto-fills host/port/username/password. User can edit fields and save as a new profile or update existing.

### Migration

No migration needed for iOS (no legacy plaintext storage like Android had).

---

## 10. File Inventory

### Services

```
Services/
├── BleEth/
│   ├── TransportAdapter.swift      (protocol)
│   ├── BleEthTransport.swift       (BLE wire protocol)
│   ├── FrameParser.swift           (frame state machine)
│   ├── DataReassembler.swift       (fragment reassembly)
│   └── QueuePipe.swift             (thread-safe byte pipe)
├── SSH/
│   ├── SSHClient.swift             (NMSSH wrapper)
│   └── SSHClientError.swift        (error enum)
└── Terminal/
    ├── TerminalEmulator.swift      (SwiftTerm wrapper)
    └── TerminalPrefs.swift         (UserDefaults)
```

### Views

```
Views/Terminal/
├── TerminalView.swift              (main SwiftUI view)
├── TerminalCanvas.swift            (Canvas-based renderer)
├── TerminalViewModel.swift         (state machine)
├── ConnectionDialog.swift          (SSH connect sheet)
├── TerminalInputHandler.swift      (key → escape sequence)
└── CredentialStore.swift           (Keychain credentials)
```

### Models

```
Models/
└── CredentialProfile.swift         (SSH credential model)
```

### Resources

```
Resources/
└── Fonts/
    └── JetBrainsMono-Regular.ttf   (bundled monospace font)
```

---

## 11. Testing

### Unit Tests

1. **FrameParser**: Feed raw bytes, assert parsed frame has correct addr/cmd/payload.
2. **DataReassembler**: Feed fragments in order, assert reassembled data matches. Feed out-of-order, assert reassembly is discarded.
3. **TerminalInputHandler**: Assert key mappings (Enter → `\r`, Ctrl+C → `0x03`, arrow keys → `\e[A/B/C/D`).

### Integration Tests (Manual)

1. BLE pair with Openterface device
2. Open Terminal tab
3. Connect via BLE-Eth to known SSH host (e.g., local Linux VM)
4. Verify:
   - SSH handshake completes
   - Shell prompt renders correctly
   - Typing produces correct characters
   - Color output (e.g., `ls --color`) renders correctly
   - Arrow keys navigate command history
   - Ctrl+C interrupts a running process
   - Pinch-to-zoom changes font size

### Performance Tests

- Run `cat` on a large file — measure FPS during rapid terminal updates
- Target: 30+ fps on iPhone 12 or newer

### Background Tests

- Background the app while SSH session is open
- Foreground it — verify session is still alive
