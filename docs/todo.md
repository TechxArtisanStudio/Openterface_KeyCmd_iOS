# Keyboard & Mouse Layout TODO

> Feature parity checklist: port Android keyboard/mouse capabilities into iOS.
> Reference Android project: `../Openterface_KeyCmd_Android/`

---

## 1. Symbol Mode Keyboard

**Android**: Dedicated symbols layout via XML (`keyboard_lower_portrait_symbols.xml`,
`keyboard_lower_landscape_symbols.xml`) with a `1234` toggle key (`0xF002`/`0xF003`)
switching between letter, symbol, and number-pad-symbol views.

**iOS**: Missing entirely — keyboard always shows letters.

- [ ] Add `KeyboardManager.isSymbolMode: Bool` published property
- [ ] Define symbol key layout mirroring Android portrait symbols:
  - Row 1: `1 2 3 4 5 6 7 8 9 0`
  - Row 2: `@ # $ _ - & + ( ) /`
  - Row 3: `= * " ' : ; ! ?  Backspace(wide)`
  - Row 4: `ABC(wide) ,(narrow) 12/34(space) Space(wide) .(narrow) Enter(wide)`
- [ ] Define symbol key layout mirroring Android landscape symbols alt:
  - Operator column (`+ - * /`) on left, number grid (`1-9 0`) on right
  - Bottom row: `ABC , !?# 0 = . Enter`
- [ ] Add `ABC` / `1234` toggle button to keyboard bottom row
- [ ] Wire symbol mode into `handleKeyPress` to send correct HID codes

**Android source files**:
- `app/src/main/res/xml/keyboard_lower_portrait_symbols.xml`
- `app/src/main/res/xml/keyboard_lower_landscape_symbols.xml`
- `app/src/main/res/xml/keyboard_lower_portrait_symbols_alt.xml`
- `app/src/main/res/xml/keyboard_lower_landscape_symbols_alt.xml`
- `CustomKeyboardView.java` — `isSymbolMode`, `showExtraPortraitKeys`

---

## 2. Fn Lock (F1-F12 via letter keys)

**Android**: `Fn` key (`0xF005`) toggles `isFnLocked`. When locked, `q→F1, w→F2, e→F3,
r→F4, t→F5, y→F6, u→F7, i→F8, o→F9, p→F10, a→F11, s→F12`. Other letter keys remain
unchanged. Key labels dynamically show "F1"-"F12" when Fn is active.

**iOS**: F1-F12 exist as a separate top row; no Fn key or Fn lock behavior.

- [ ] Add `KeyboardManager.isFnLocked: Bool` published property
- [ ] Add `Fn` key to bottom row (replace one Ctrl or add beside Space)
- [ ] In `handleKeyPress`, resolve Fn mapping when `isFnLocked` is true
- [ ] Update key display labels dynamically to show F1-F12 when Fn locked
- [ ] Fn lock should NOT affect modifier keys (Ctrl, Shift, Alt, Cmd), Space, Enter, Backspace

**Android source files**:
- `CustomKeyboardView.java:882-909` — `resolveFnMapping()`
- `CustomKeyboardView.java:872-879` — `getFnDisplayLabel()`, `getFnDisplayIconResId()`

---

## 3. Key Long-Press Alternates Popup

**Android**: Long-pressing a single-char key shows a popup with alternate characters.
- `keyAlternates` XML attribute: comma-separated list (e.g., `"@,$,%,^"`)
- `keyCornerHint` XML attribute: hint shown in corner of key
- Popup shows: symbol → alternates → base label ordering
- Drag finger to select; slide above/beyond cancel threshold to dismiss
- Default selection prefers `keyAlternates` first value, then base label

**iOS**: Missing entirely — no alternate character selection on long-press.

- [ ] Define `KeyDefinition` struct with label, symbolLabel, alternates, cornerHint, keyCode
- [ ] Build key definitions table matching Android XML `keyAlternates` values:
  - `q` → Q, 1 | `w` → W, 2 | `e` → E, 3 | ... | `p` → P, 0
  - `a` → A, @ | `s` → S, # | `d` → D, $ | `f` → F, % | ...
  - `k` → K, (, {, [, < | `l` → L, ), }, ], >
  - `,` → ;, -, : | `.` → ', =, "
  - `/` → ?, +, `, ~
- [ ] Create `KeyAlternatesPopup` SwiftUI view (horizontal bubble strip)
- [ ] Add long-press gesture recognizer to each key button
- [ ] Implement drag-to-select within popup, cancel on drag outside
- [ ] Send correct HID code + shift modifier for selected character

**Android source files**:
- `CustomKeyboardView.java:835-852` — `shouldEnableAlternates()`
- `CustomKeyboardView.java:942-993` — `showAlternatesPopup()`
- `CustomKeyboardView.java:995-1023` — `buildAlternateOptions()`
- `CustomKeyboardView.java:1049-1079` — `updateAlternateSelection()`
- `CustomKeyboardView.java:1141-1195` — `mapAsciiAlternate()`

---

## 4. Swipeable Shortcut Profile Panels

**Android**: Paginated 7-column x 2-row panels above the keyboard. Swipeable
left/right with edge resistance. Default panel has: ALL, COPY, CUT, PASTE, SAVE, UP,
UNDO / ESC, CTRL, ALT, TAB, LEFT, DOWN, RIGHT. Additional panels from
`ShortcutProfileManager` profiles (up to 14 shortcuts per page).

**iOS**: Simple horizontal `ScrollView` of `.bordered` buttons (Alt+F4, Ctrl+Alt+Del,
Win+L, Win+D, etc.) — not paginated, not swipeable, no profile support.

- [ ] Create `ShortcutPanel` SwiftUI view (7×2 grid with icons)
- [ ] Create `ShortcutPanelPager` with swipe gesture + pagination animation
- [ ] Build default panel keys matching Android `buildStandardTopPanelKeys()`:
  - Row 1: ALL(Cmd+A), COPY, CUT, PASTE, SAVE, UP, UNDO
  - Row 2: ESC, CTRL, ALT, TAB, LEFT, DOWN, RIGHT
- [ ] Integrate `ShortcutProfileManager` for custom profile panels
- [ ] Add edge resistance when swiping past first/last page (0.35x factor)
- [ ] Use 140ms animation for panel transitions
- [ ] Panel buttons show pressed state for active modifier locks

**Android source files**:
- `CustomKeyboardView.java:1397-1464` — `rebuildTopShortcutPanels()`, `addProfilePanels()`
- `CustomKeyboardView.java:1466-1485` — `buildStandardTopPanelKeys()`
- `CustomKeyboardView.java:1584-1627` — `createTopPanelTouchListener()` (swipe logic)
- `CustomKeyboardView.java:1629-1756` — drag resistance, swipe finish, animation

---

## 5. Key Repeat on Long-Press

**Android**: Arrow keys and Backspace auto-repeat on long-press.
- Initial long-press timeout: `ViewConfiguration.getLongPressTimeout()` (~400ms)
- Repeat interval: 10ms between repeats
- `isRepeatable` XML attribute controls which keys repeat

**iOS**: Missing — key press fires once regardless of hold duration.

- [ ] Add `KeyRepeatController` class managing repeat timer
- [ ] Configure repeatable keys: arrow keys (Up, Down, Left, Right), Backspace
- [ ] On long-press (>400ms), start repeating at 10ms interval
- [ ] On finger lift, stop repeating
- [ ] Apply to both main keyboard and extra keys panel

**Android source files**:
- `CustomKeyboardView.java:2097-2119` — `startRepeatingDelete()`, `stopRepeatingDelete()`
- `CustomKeyboardView.java:927-936` — `shouldRepeatOnLongPress()`

---

## 6. Target OS Key Label Switching

**Android**: Key labels change based on target OS setting:
- Windows: `Win` with Windows icon
- macOS: `Cmd` with Apple icon
- Linux: `Super` with Linux icon

**iOS**: Key always shows "Cmd" — no dynamic switching needed since iOS targets macOS,
but should align with Android's configurable `target_os` preference for cross-platform consistency.

- [ ] Read `target_os` from user defaults (default: `macos`)
- [ ] Update Win/Cmd key label based on target OS
- [ ] Update shortcut panel labels (Cmd+A vs Ctrl+A) based on target OS
- [ ] Use appropriate SF Symbol for the modifier key icon

**Android source files**:
- `CustomKeyboardView.java:237-262` — `applyTargetOsLabels()`

---

## 7. Split Keyboard Mode (Stretch Goal)

**Android**: Landscape split mode divides keyboard into left/right halves with
touchpad in the middle. Modifier states sync between halves. Top shortcut panel
shared across both halves.

**iOS**: Not implemented.

- [ ] Create `SplitKeyboardView` with left/right halves
- [ ] Divide keyboard rows at midpoint
- [ ] Sync modifier lock states between left and right halves
- [ ] Shared touchpad section in center
- [ ] Shared top shortcut panel above split

**Android source files**:
- `CustomKeyboardView.java:65-71` — `SPLIT_NONE`, `SPLIT_LEFT`, `SPLIT_RIGHT`
- `CustomKeyboardView.java:272-294` — `setSplitPart()`, `setSplitPartner()`
- `CustomKeyboardView.java:521-544` — split key filtering and width rescaling
- `fragment_composite_split.xml` — layout definition

---

## 8. Corner Hints on Keys

**Android**: Each key can show a `keyCornerHint` in the top-right corner (small,
low-opacity text) indicating the primary alternate character.

**iOS**: Missing.

- [ ] Add optional corner hint overlay to key buttons
- [ ] Style: 10sp, 20% opacity, bold, top-right aligned
- [ ] Only show when popup is not visible and no Fn label shown

**Android source files**:
- `CustomKeyboardView.java:712-735` — corner hint view creation

---

## Visual Design Reference (Android → iOS)

| Element | Android | iOS Target |
|---------|---------|------------|
| Key background | `@drawable/key_background` (flat, no shadow) | `UIColor.secondarySystemBackground` (matches current) |
| Pressed state | `@drawable/press_button_background` | `Color.blue` (matches current) |
| Function keys | `@drawable/function_button_background` | `Color(UIColor.tertiarySystemBackground)` |
| Key margin | 2dp | 2pt |
| Key font size | 14sp (11sp for INS/PGUP/etc.) | `Font.system(size: 12)` / `Font.caption2` |
| Corner hint | 10sp, 20% alpha, bold | `Font.caption2`, `.opacity(0.2)` |
| Touchpad tips | 11sp, `@color/text_secondary` | `.font(.caption2)`, `.foregroundColor(.secondary)` |
| Toggle handle pill | 40dp × 4dp (portrait), 4dp × 40dp (landscape) | 28×4pt / 4×48pt (matches current) |
| Haptic feedback | `HapticFeedbackConstants.KEYBOARD_TAP` | `UIImpactFeedbackGenerator` (current) |

---

## Implementation Priority

1. **High Priority** — Core UX improvements users interact with every session:
   - Symbol Mode
   - Fn Lock
   - Key Long-Press Alternates
   - Key Repeat on Long-Press

2. **Medium Priority** — Workflow enhancements:
   - Swipeable Shortcut Panels
   - Target OS Label Switching
   - Corner Hints

3. **Low Priority** — Nice-to-have / specialized use:
   - Split Keyboard Mode

---

## Test Plan

Each feature should be tested with:

1. **Portrait orientation**: Verify layout renders correctly
2. **Landscape orientation**: Verify layout adapts (F-row hidden, spacing correct)
3. **Keyboard-only mode**: Extra keys panel visible
4. **Both mode**: Touchpad + keyboard coexist
5. **Touchpad-only mode**: Touchpad fills screen
6. **Modifier state**: Shift/Ctrl/Alt/Cmd toggle and visual feedback
7. **HID packet verification**: Correct bytes sent via BLE for each key type
