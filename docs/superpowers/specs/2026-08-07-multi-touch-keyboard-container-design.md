# Multi-Touch Keyboard Container Design

**Date**: 2026-08-07
**Status**: Proposed
**Author**: Claude + User

## Problem Statement

When using the KeyCmd iOS app in momentary-chord modifier mode, pressing and holding the Cmd key while pressing Tab with another finger causes both keys to be released unexpectedly. The user must keep Cmd held to cycle through apps with repeated Tab presses, but the Cmd modifier state is lost as soon as Tab is pressed.

**Symptoms**:
- Both Cmd and Tab are released immediately when Tab is pressed
- Tab sometimes does not register at all when Cmd is held
- Issue occurs 100% of the time
- Occurs in both portrait and landscape orientations
- Specific to Cmd+Tab combination (other Cmd+key combos not yet verified)

**Root Cause Analysis**:

The keyboard UI uses `PressDetectorView` (a `UIViewRepresentable` wrapping `UILongPressGestureRecognizer`) on each individual key. When the user holds Cmd and then presses Tab:

1. Cmd's gesture recognizer enters `.began` state and tracks the first touch
2. When the second finger touches Tab, iOS's gesture recognition system may fail to route the touch to Tab's separate gesture recognizer
3. Alternatively, Cmd's touch may be implicitly cancelled when a new touch arrives

This is a fundamental limitation of using multiple independent `UILongPressGestureRecognizer` instances for multi-touch scenarios. The comment in the code acknowledges this: "UIKit-backed press detector to avoid SwiftUI gesture cancellation during multi-touch" — but the UIKit solution itself has multi-touch limitations when spread across separate views.

## Solution: Unified Multi-Touch Container

Replace the per-key `PressDetectorView` instances with a single `MultiTouchKeyboardContainer` that covers the entire keyboard area and handles all multi-touch events centrally.

### Architecture Overview

**Current architecture** (problematic):
```
Keyboard VStack
  └── Row 1 HStack
        ├── KeyButton (PressDetectorView #1 - UILongPressGestureRecognizer)
        ├── KeyButton (PressDetectorView #2 - UILongPressGestureRecognizer)
        └── ...
  └── Row 2 HStack
        └── ...
```
Each key has its own gesture recognizer → recognizers compete for touches → multi-touch fails.

**New architecture**:
```
ZStack
  ├── Visual layer (VStack of HStacks) — pure rendering, no gesture handling
  └── MultiTouchKeyboardContainer (UIView) — unified touch layer
        - Covers entire keyboard area
        - isMultipleTouchEnabled = true
        - Overrides touchesBegan/Moved/Ended/Cancelled
        - Maps touch coordinates to key identities
        - Dispatches press/release events to appropriate handlers
```

The visual layer and touch layer are decoupled:
- Visual layer continues using SwiftUI to render key appearance (preserves existing code)
- Touch layer uses UIKit to handle all touches centrally
- The two layers communicate via a "key registration table" that maps key identities to frame positions

### Touch Event Handling

**Touch lifecycle**:

```
touchesBegan:
  for each touch:
    1. Get touch location in container coordinate space
    2. Query key registry → obtain keyIdentity
    3. Create TouchState(touch, keyIdentity, startTime)
    4. Store in activeTouches dictionary [UITouch: TouchState]
    5. Fire onPress(keyIdentity)

touchesMoved:
  for each touch:
    1. Get new location
    2. Query key at new location → new keyIdentity
    3. If keyIdentity changed (finger slid to different key):
       - Fire onRelease for old key
       - Fire onPress for new key
       - Update TouchState
    4. If keyIdentity unchanged but key is a modifier needing slide-to-lock detection:
       - Fire onMoved(touch location)

touchesEnded / touchesCancelled:
  for each touch:
    1. Look up corresponding TouchState
    2. Fire onRelease(keyIdentity)
    3. Remove from activeTouches
```

**Key properties**:
- Each finger tracked independently, no interference
- Touch cancellation (e.g., system gesture interrupt) correctly releases the corresponding key
- Supports finger sliding between keys (used for modifier slide-to-lock gesture)

### Key Registration and Coordinate Mapping

**Key Registration Table (KeyFrameRegistry)**:

The visual layer registers each key's information with the touch layer during layout:

```swift
struct KeyRegistration {
    let keyId: String          // Unique identifier, e.g. "cmd_left", "tab", "a"
    let keyName: String        // Key name sent to KeyboardManager, e.g. "Cmd", "Tab", "A"
    let keyType: KeyType       // .modifier / .regular / .special
    let frame: CGRect          // Position in touch layer coordinate space
}
```

**Coordinate mapping strategy**:

The keyboard layout is a regular grid (rows + columns), so mathematical computation is used rather than depending on SwiftUI layout callbacks:

```swift
struct KeyboardLayoutMetrics {
    let containerFrame: CGRect      // Touch layer's own position
    let rowHeights: [CGFloat]       // Height of each row (or proportions)
    let keyWidths: [[CGFloat]]      // Width of each key per row (or proportions)
    let spacing: CGFloat            // Row and key spacing
    let padding: EdgeInsets         // Inset padding
}
```

The touch layer computes each key's frame from layout metrics. When a touch occurs:
1. Iterate through all registered key frames
2. Find the key containing the touch point
3. Return that key's keyName and keyType

**Key type behavior mapping**:

| KeyType | onPress behavior | onRelease behavior | onMoved behavior |
|---------|-----------------|-------------------|-----------------|
| `.modifier` | Momentary: handleKeyDown or addModifierTrackedOnly; Sticky: no-op | Momentary: handleKeyUp or lockModifier; Sticky: toggle lock | Detect slide-to-lock |
| `.regular` | handleKeyDown or startKeyRepeat | handleKeyUp or stopKeyRepeat | no-op |
| `.special` (Caps, Esc) | handleSpecialKey | no-op | no-op |

### Integration with Existing Code

**Scope of changes**:

1. **New: `MultiTouchKeyboardContainer`** (UIViewRepresentable)
   - Approximately 200-300 lines
   - Contains touch tracking, key mapping, event dispatch logic

2. **Modified: `BasicKeyboardMouseView`**
   - Visual layer removes all `PressDetectorView` instances
   - Replace with `ModifierKeyVisual` and `KeyVisual` (render only, no touch handling)
   - Wrap keyboard in `ZStack`, overlay `MultiTouchKeyboardContainer`
   - Register key frames with container after layout completes

3. **KeyboardManager unchanged**
   - `handleKeyDown`, `handleKeyUp`, `handleModifierToggle` etc. API unchanged
   - `MultiTouchKeyboardContainer` calls these existing APIs directly

**Code structure outline**:

```swift
// BasicKeyboardMouseView after refactoring
ZStack {
    // Visual layer: pure rendering, no gestures
    VStack(spacing: 6) {
        HStack(spacing: 3) {
            KeyVisual(key: "Esc")    // Pure visual
            KeyVisual(key: "F1")
            // ...
        }
        // ... other rows
    }
    
    // Touch layer: unified multi-touch
    MultiTouchKeyboardContainer(
        keyRegistrations: computeKeyRegistrations(),
        onPress: { keyName, keyType in
            handleKeyPress(keyName, keyType)
        },
        onRelease: { keyName, keyType in
            handleKeyRelease(keyName, keyType)
        },
        onMoved: { point, keyName in
            handleTouchMoved(point, keyName)
        }
    )
}
```

**Backward compatibility**:
- Pro keyboard view (`ProKeyboardMouseView`) can be migrated later; this change focuses on Basic view first
- Sticky mode, momentary-chord mode, slide-to-lock, long-press repeat all preserved
- Visual appearance completely unchanged

### Edge Cases and Error Handling

1. **Touch cancellation (system gesture interrupt)**
   - When system gestures (e.g., edge swipe back) interrupt a touch, `touchesCancelled` must release all keys pressed by that touch
   - Modifier keys must be removed from `activeModifiers`
   - Long-press repeat must be stopped

2. **Finger slides out of keyboard area**
   - If a finger slides outside `MultiTouchKeyboardContainer`'s bounds, iOS automatically calls `touchesEnded` or `touchesCancelled`
   - Ensure keys are released correctly

3. **Modifier slide-to-lock gesture**
   - In `touchesMoved`, detect whether finger has slid into the lock icon region
   - Lock icon position must be provided during registration (offset relative to modifier key frame)
   - After locking, the current touch's `onRelease` must not unlock (use `justLocked` flag)

4. **Key frame updates**
   - When screen rotates, keyboard layout switches, or window size changes, key frames change
   - `MultiTouchKeyboardContainer` must respond to layout changes and recompute frames
   - Use SwiftUI's `GeometryReader` or `onGeometryChange` to trigger updates

5. **Multiple fingers on same key**
   - Theoretically possible but practically harmless
   - Each finger tracked independently; first finger down triggers `onPress`, last finger up triggers `onRelease`
   - Intermediate lifts do not trigger (use reference counting)

6. **BLE send failure**
   - Consistent with existing logic; not handled at touch layer
   - BLE layer's retry/error handling remains unchanged

## Implementation Notes

- The unified touch container should be implemented as a `UIViewRepresentable` wrapping a custom `UIView` subclass
- The custom UIView should override `touchesBegan(_:with:)`, `touchesMoved(_:with:)`, `touchesEnded(_:with:)`, and `touchesCancelled(_:with:)`
- `isMultipleTouchEnabled` must be set to `true` on the UIView
- The touch layer should be transparent (`backgroundColor = .clear`) and not interfere with visual rendering
- Key registration should happen in a layout pass (e.g., after `GeometryReader` provides size information)
- The design should be testable by mocking `KeyboardManager` and verifying touch-to-event mapping

## Future Work

- Migrate `ProKeyboardMouseView` to use the same unified touch container
- Consider extracting the touch container into a reusable component for other views (numpad, gamepad)
- Add visual debugging overlay to show touch points and key hit-test results during development
