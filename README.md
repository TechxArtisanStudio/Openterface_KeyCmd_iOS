# KeyCmd for iOS

English | [简体中文](README.zh-CN.md)

KeyCmd is the companion iOS app for [Openterface](https://openterface.com) hardware -- a USB/Bluetooth KVM-style bridge that lets you control a target computer from your iPhone. The app sends HID keyboard, mouse, and gamepad commands over Bluetooth Low Energy (BLE) to the Openterface KVM device.

**Requirements:** iOS 17.0+, iPhone with BLE, Openterface KVM hardware

---

## Features at a Glance

| Area | Capabilities |
|------|-------------|
| **Keyboard & Mouse** | Full QWERTY, OS-specific layouts (Win/mac/Linux), touchpad, scroll strips, numpad, modifier modes (sticky / momentary-chord), Fn lock, key repeat, long-press alternates |
| **Gamepad** | Xbox / PlayStation / NES skins, dual analog sticks, D-pad, editable layout, custom key mapping, portrait & landscape |
| **Shortcut Hub** | Profiles for Blender, KiCAD, Fusion 360, Photoshop, VS Code, Nomad; create/import/export/custom shortcuts, favorites, drag-and-drop |
| **Macros** | Record & replay key sequences, composite/special tokens, scheduling, repeating, nesting |
| **Voice Input** | Apple Speech / Whisper STT, AI text refinement (OpenAI-compatible), auto-send to target, clipboard integration, Unicode support |
| **Customization** | 8 accent color themes, dark/light mode, rows 2-3 strip profiles, haptic feedback, scroll sensitivity |

---

## Screenshots

### Welcome & Keyboard

| Welcome | Keyboard Basic | Pro Keyboard |
|:---:|:---:|:---:|
| Welcome screen with mode selection | Basic QWERTY keyboard | Pro keyboard with shortcut strip |

### Touchpad & Gamepad

| Touchpad | Gamepad | Numpad |
|:---:|:---:|:---:|
| Touchpad with mouse buttons & scroll strip | Xbox/PS/NES gamepad layouts | Numeric keypad |

### Shortcut Hub & Voice

| Shortcut Hub | Macros | Voice Input |
|:---:|:---:|:---:|
| Shortcut profiles & editor | Macro creation & scheduler | Voice-to-text with AI refinement |

---

## Quick Start

1. **Pair** your iPhone with the Openterface KVM device via BLE (the app scans automatically on launch).
2. **Select a mode** from the launch panel: Keyboard & Mouse, Gamepad, Shortcuts, Macros, or Voice Input.
3. **Set the target OS** (Windows / macOS / Linux) so modifier keys and Unicode input match your machine.
4. **Start controlling** your target computer.

---

## Modes

### Keyboard & Mouse

- **Basic mode** -- dedicated full-screen keyboard with touchpad, no app header
- **Pro mode** -- composite layout with shortcut strips and OS-specific shortcut buttons
- **Modifier behavior**: choose between **sticky** (tap to toggle) or **momentary-chord** (press-and-hold, slide-to-lock)
- **Chord sustain**: control when HID modifier-down is sent -- immediately or only when a regular key is chorded
- **Fn Lock**: locks letter keys to F1-F12
- **Key repeat**: hold any key for auto-repeat with configurable delay and interval
- **Long-press alternates**: press and hold symbol keys to access alternate characters via a 3x3 picker
- **Target OS setting**: switches modifier labels (Win / Cmd / Super) and Unicode input method

### Touchpad

- Relative mouse movement via gesture
- Left / Middle / Right buttons with hold and lock modes
- Drag mode toggle for drag-and-drop
- Double click support
- Vertical and horizontal scroll strips
- Configurable scroll sensitivity
- Pointer tip visual feedback with glow border

### Gamepad

- Three skins: **Xbox**, **PlayStation**, **NES**
- **Left analog stick** maps to WASD with composite diagonal support and hysteresis
- **Right analog stick** controls mouse movement with dynamic acceleration
- **D-Pad** mapped to arrow keys
- **Shoulder & trigger** buttons (LB/RB/LT/RT or L1/R1/L2/R2)
- **Editable layout** -- drag components to reposition
- **Custom key mapping** -- remap any button
- Portrait and landscape orientations

### Shortcut Hub

- **Built-in profiles**: Common, VS Code, Blender, KiCad, Fusion 360, Photoshop, Nomad
- **Create custom profiles** with categories and color-coded tabs
- **Import / Export** profiles via JSON and iOS share sheet
- **"My Shortcuts"** favorites system per profile
- **Shortcut editor** with modifier selection (Cmd/Ctrl/Shift/Alt) and key picker (A-Z, F1-F12, special keys)
- **List and card** display modes with drag-and-drop reordering

### Macros

- Create macros with a label and key sequence
- **Composite key syntax**: `<CTRL>A</CTRL>` means press Ctrl, press A, release all
- **Special tokens**: `<ESC>`, `<BACK>`, `<ENTER>`, `<SPACE>`, `<LEFT>`, `<RIGHT>`, `<UP>`, `<DOWN>`, `<HOME>`, `<END>`, `<DELAY1S>`, `<DELAY2S>`, `<DELAY5S>`, `<DELAY10S>`
- **Modifier tags**: `<CTRL>`, `<SHIFT>`, `<ALT>`, `<CMD>`, `<WIN>` with closing tags
- **Macro nesting** via `<Macro>label</Macro>` references
- **Scheduling**: run at a specific date/time
- **Repeating**: N times or at intervals (30s, 1m, 5m, 10m, 30m, 1h)
- Background thread execution for strict token ordering

### Voice Input

- **STT engines**: Apple Speech (built-in) or Whisper (on-device ML via WhisperKit)
- **Auto-pause on silence** detection
- **AI text refinement** via OpenAI-compatible API for cleaner output
- **Auto-send** transcribed text directly to the target machine
- **History** of sent voice inputs with edit, resend, and save-as-macro actions
- **Special token quick-insert** buttons in the toolbar

---

## Settings

| Category | Options |
|----------|---------|
| **General** | Clipboard monitoring (send clipboard content to target via Unicode), haptic feedback toggle, theme selection |
| **Keyboard** | Modifier behavior (sticky / momentary-chord), chord sustain, long-press repeat mode |
| **Voice Input** | STT engine selection, Whisper model management |
| **AI Settings** | Provider configuration (name, API base, model, API key), system prompt roles, custom prompt editing, API connection test, request history |

---

## Customization

- **Theme system**: 8 accent color families (Orange, Blue, Green, Pink, Purple, Red, Teal, Indigo) with dark/light mode (follow system or manual override)
- **Rows 2-3 Strip Profiles**: Remap the keyboard shortcut strip rows with custom pages of F-keys, navigation, and punctuation slots
- **Haptic feedback**: Light taps for buttons, rigid ticks for scroll, medium for special actions, strong for macro execution

---

## Connection

KeyCmd connects to the Openterface KVM device exclusively via **Bluetooth Low Energy (BLE)**:

1. Ensure the Openterface KVM device is powered on and broadcasting BLE
2. The app automatically scans for devices with names starting with "openterface" or "kvm"
3. Tap the device to connect; RSSI signal strength is monitored in real time
4. HID keyboard and mouse data is sent via the FFF2 BLE characteristic

---

## Technical Details

| Item | Detail |
|------|--------|
| **Package** | com.openterface.keycmd |
| **Min OS** | iOS 17.0 |
| **HID Protocol** | CH9329 UART over BLE |
| **BLE Characteristic** | FFF2 |
| **STT Engine** | Apple SFSpeechRecognizer / WhisperKit (local ML) |
| **AI Provider** | OpenAI-compatible API (configurable base URL, model, key) |
| **Unicode** | Windows Alt+NumpadHex, macOS Option+Hex, Linux Ctrl+Shift+U+Hex |
| **Core Library** | Openterface C core (HID mapping, script tokenization) via submodule |

---

## Building from Source

```bash
git clone --recurse-submodules https://github.com/TechxArtisan/Openterface_KeyCmd_iOS.git
cd Openterface_KeyCmd_iOS
```

1. Open `KeyCmd.xcodeproj` in Xcode
2. Select your development team for code signing
3. Build and run on a physical iPhone (BLE is not available on Simulator)

---

## Upstream

Learn more about the Openterface hardware at [openterface.com](https://openterface.com)
