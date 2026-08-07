# Multi-Touch Keyboard Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-key `PressDetectorView` instances in the Basic keyboard with a unified multi-touch container so that holding Cmd while pressing Tab correctly maintains the Cmd modifier state.

**Architecture:** A single `UIView` subclass (`MultiTouchKeyboardContainerView`) with `isMultipleTouchEnabled = true` covers the entire keyboard area. It overrides `touchesBegan/Moved/Ended/Cancelled`, maps each `UITouch` to a key via a coordinate-based hit-test, and dispatches press/release events through closures. The existing SwiftUI keyboard layout remains as a pure visual layer underneath.

**Tech Stack:** Swift 5.9, UIKit (UIView + UIGesture handling), SwiftUI (UIViewRepresentable bridge), XCTest

## Global Constraints

- iOS 17.0+ minimum deployment target
- Must not break Pro keyboard view (`ProKeyboardMouseView`) — only modify Basic keyboard
- Existing `KeyboardManager` API surface must not change
- Modifier behaviors (sticky, momentary-chord, slide-to-lock) must all continue working
- Long-press key repeat must continue working
- Visual appearance must be identical before and after

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `KeyCmd/View/MultiTouch/KeyType.swift` | `KeyType` enum (`.modifier`, `.regular`, `.special`) and `KeyRegistration` struct |
| `KeyCmd/View/MultiTouch/KeyFrameRegistry.swift` | Computes key frames from layout metrics, performs hit-testing |
| `KeyCmd/View/MultiTouch/TouchTracker.swift` | Tracks active `UITouch` → key mappings, fires callbacks |
| `KeyCmd/View/MultiTouch/MultiTouchKeyboardContainerView.swift` | UIKit `UIView` subclass handling multi-touch |
| `KeyCmd/View/MultiTouch/MultiTouchKeyboardContainer.swift` | `UIViewRepresentable` bridge for SwiftUI |
| `KeyCmdTests/KeyFrameRegistryTests.swift` | Unit tests for frame computation and hit-testing |
| `KeyCmdTests/TouchTrackerTests.swift` | Unit tests for touch tracking logic |

### Modified files

| File | Changes |
|------|---------|
| `KeyCmd/View/BasicKeyboardMouseView.swift` | Wrap keyboard in `ZStack`, add `MultiTouchKeyboardContainer` overlay, replace `ModifierKeyButton`/`KeyPressButton` with visual-only views |

---

### Task 1: Key Type and Registration Data Structures

**Files:**
- Create: `KeyCmd/View/MultiTouch/KeyType.swift`
- Test: `KeyCmdTests/KeyFrameRegistryTests.swift`

- [ ] **Step 1: Create test file with failing tests for KeyType and KeyRegistration**

```swift
// KeyCmdTests/KeyFrameRegistryTests.swift
import XCTest
@testable import KeyMod

final class KeyFrameRegistryTests: XCTestCase {

    func testKeyTypeModifier() {
        let reg = KeyRegistration(
            keyId: "cmd_left",
            keyName: "Cmd",
            keyType: .modifier,
            frame: CGRect(x: 0, y: 0, width: 50, height: 40)
        )
        XCTAssertEqual(reg.keyType, .modifier)
        XCTAssertEqual(reg.keyName, "Cmd")
    }

    func testKeyTypeRegular() {
        let reg = KeyRegistration(
            keyId: "tab",
            keyName: "Tab",
            keyType: .regular,
            frame: CGRect(x: 0, y: 0, width: 50, height: 40)
        )
        XCTAssertEqual(reg.keyType, .regular)
    }

    func testKeyTypeSpecial() {
        let reg = KeyRegistration(
            keyId: "caps",
            keyName: "Caps",
            keyType: .special,
            frame: CGRect(x: 0, y: 0, width: 50, height: 40)
        )
        XCTAssertEqual(reg.keyType, .special)
    }

    func testHitTestInsideKey() {
        let registry = KeyFrameRegistry()
        registry.register(KeyRegistration(
            keyId: "tab",
            keyName: "Tab",
            keyType: .regular,
            frame: CGRect(x: 10, y: 20, width: 50, height: 40)
        ))
        let result = registry.hitTest(CGPoint(x: 30, y: 35))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.keyName, "Tab")
    }

    func testHitTestOutsideKey() {
        let registry = KeyFrameRegistry()
        registry.register(KeyRegistration(
            keyId: "tab",
            keyName: "Tab",
            keyType: .regular,
            frame: CGRect(x: 10, y: 20, width: 50, height: 40)
        ))
        let result = registry.hitTest(CGPoint(x: 100, y: 100))
        XCTAssertNil(result)
    }

    func testHitTestMultipleKeys() {
        let registry = KeyFrameRegistry()
        registry.register(KeyRegistration(
            keyId: "cmd",
            keyName: "Cmd",
            keyType: .modifier,
            frame: CGRect(x: 0, y: 0, width: 50, height: 40)
        ))
        registry.register(KeyRegistration(
            keyId: "tab",
            keyName: "Tab",
            keyType: .regular,
            frame: CGRect(x: 60, y: 0, width: 50, height: 40)
        ))
        let cmdHit = registry.hitTest(CGPoint(x: 25, y: 20))
        XCTAssertEqual(cmdHit?.keyName, "Cmd")
        let tabHit = registry.hitTest(CGPoint(x: 80, y: 20))
        XCTAssertEqual(tabHit?.keyName, "Tab")
    }

    func testHitTestLastRegisteredWins() {
        // When two keys overlap (shouldn't happen, but defensive), later registration wins
        let registry = KeyFrameRegistry()
        registry.register(KeyRegistration(
            keyId: "a", keyName: "A", keyType: .regular,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        ))
        registry.register(KeyRegistration(
            keyId: "b", keyName: "B", keyType: .regular,
            frame: CGRect(x: 50, y: 50, width: 100, height: 100)
        ))
        let result = registry.hitTest(CGPoint(x: 75, y: 75))
        XCTAssertEqual(result?.keyName, "B")
    }

    func testClearRegistrations() {
        let registry = KeyFrameRegistry()
        registry.register(KeyRegistration(
            keyId: "a", keyName: "A", keyType: .regular,
            frame: CGRect(x: 0, y: 0, width: 50, height: 40)
        ))
        registry.clear()
        let result = registry.hitTest(CGPoint(x: 25, y: 20))
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyCmdTests/KeyFrameRegistryTests 2>&1 | tail -20`
Expected: Build failure — `KeyRegistration`, `KeyType`, `KeyFrameRegistry` not found.

- [ ] **Step 3: Create KeyType.swift with data structures**

```swift
// KeyCmd/View/MultiTouch/KeyType.swift
import CoreGraphics

/// Classification of a keyboard key for touch dispatch.
enum KeyType {
    /// Modifier key (Ctrl, Shift, Alt, Cmd, Win, Option, Super).
    /// Supports slide-to-lock in momentary-chord mode.
    case modifier
    /// Regular key (letters, numbers, symbols, Tab, Enter, Backspace, arrows, F-keys).
    /// Supports long-press repeat.
    case regular
    /// Special key with custom behavior (Caps Lock toggle).
    case special
}

/// A registered key with its identity, type, and frame in the touch container's coordinate space.
struct KeyRegistration {
    let keyId: String
    let keyName: String
    let keyType: KeyType
    let frame: CGRect
}
```

- [ ] **Step 4: Create KeyFrameRegistry with hit-testing**

```swift
// KeyCmd/View/MultiTouch/KeyFrameRegistry.swift
import CoreGraphics

/// Stores key registrations and performs coordinate-based hit-testing.
/// Thread-safe: all access is on the main thread (UI touch events).
final class KeyFrameRegistry {
    private var registrations: [KeyRegistration] = []

    func register(_ registration: KeyRegistration) {
        registrations.append(registration)
    }

    func clear() {
        registrations.removeAll()
    }

    /// Returns the key at the given point, or nil if no key contains the point.
    /// If multiple keys overlap, the last registered key wins.
    func hitTest(_ point: CGPoint) -> KeyRegistration? {
        // Iterate in reverse so later registrations (drawn on top) take priority
        for reg in registrations.reversed() {
            if reg.frame.contains(point) {
                return reg
            }
        }
        return nil
    }

    /// All currently registered keys.
    var allKeys: [KeyRegistration] { registrations }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyCmdTests/KeyFrameRegistryTests 2>&1 | tail -20`
Expected: All 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add KeyCmd/View/MultiTouch/KeyType.swift KeyCmd/View/MultiTouch/KeyFrameRegistry.swift KeyCmdTests/KeyFrameRegistryTests.swift
git commit -m "feat: add key registration data structures and hit-testing

KeyFrameRegistry stores key frames and performs coordinate-based
hit-testing for the multi-touch keyboard container."
```

---

### Task 2: Key Frame Computation from Layout Metrics

**Files:**
- Modify: `KeyCmd/View/MultiTouch/KeyFrameRegistry.swift` (add `computeFrames` method)
- Modify: `KeyCmdTests/KeyFrameRegistryTests.swift` (add frame computation tests)

- [ ] **Step 1: Add failing tests for frame computation**

Append to `KeyCmdTests/KeyFrameRegistryTests.swift`:

```swift
    func testComputeFramesForSimpleGrid() {
        // 2 rows × 3 keys, equal width, spacing 3, padding 0
        let layout = KeyboardLayoutDescription(
            rows: [
                ["A", "B", "C"],
                ["D", "E", "F"]
            ],
            containerSize: CGSize(width: 306, height: 206), // 3 keys × 100 + 2×3 spacing = 306; 2 rows × 100 + 1×6 spacing = 206
            rowSpacing: 6,
            keySpacing: 3,
            padding: .zero,
            fixedRowHeights: [],
            fixedKeyWidths: [:]
        )
        let registry = KeyFrameRegistry()
        registry.computeFrames(from: layout, keyTypeResolver: { _ in .regular })

        // Key "A" should be at (0, 0) with size 100×100
        let aHit = registry.hitTest(CGPoint(x: 50, y: 50))
        XCTAssertEqual(aHit?.keyName, "A")

        // Key "B" should be at (103, 0) — after A (100) + spacing (3)
        let bHit = registry.hitTest(CGPoint(x: 150, y: 50))
        XCTAssertEqual(bHit?.keyName, "B")

        // Key "D" should be at (0, 106) — after row 1 (100) + spacing (6)
        let dHit = registry.hitTest(CGPoint(x: 50, y: 150))
        XCTAssertEqual(dHit?.keyName, "D")
    }

    func testComputeFramesWithPadding() {
        let layout = KeyboardLayoutDescription(
            rows: [["X"]],
            containerSize: CGSize(width: 116, height: 58),
            rowSpacing: 6,
            keySpacing: 3,
            padding: EdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 0),
            fixedRowHeights: [],
            fixedKeyWidths: [:]
        )
        let registry = KeyFrameRegistry()
        registry.computeFrames(from: layout, keyTypeResolver: { _ in .regular })

        // Key "X" should be at (8, 8) after padding, size 100×42
        let xHit = registry.hitTest(CGPoint(x: 50, y: 25))
        XCTAssertEqual(xHit?.keyName, "X")
        // Outside padding should not hit
        let miss = registry.hitTest(CGPoint(x: 2, y: 2))
        XCTAssertNil(miss)
    }

    func testComputeFramesWithFixedRowHeights() {
        // 2 rows: first row fixed at 30pt, second row fills remaining
        let layout = KeyboardLayoutDescription(
            rows: [["A", "B"], ["C", "D"]],
            containerSize: CGSize(width: 203, height: 136), // 200 + 3 spacing = 203; 30 + 6 + 100 = 136
            rowSpacing: 6,
            keySpacing: 3,
            padding: .zero,
            fixedRowHeights: [30], // first row is 30pt
            fixedKeyWidths: [:]
        )
        let registry = KeyFrameRegistry()
        registry.computeFrames(from: layout, keyTypeResolver: { _ in .regular })

        // Row 1 at y=0..30
        let aHit = registry.hitTest(CGPoint(x: 50, y: 15))
        XCTAssertEqual(aHit?.keyName, "A")

        // Row 2 at y=36..136 (30 + 6 spacing)
        let cHit = registry.hitTest(CGPoint(x: 50, y: 80))
        XCTAssertEqual(cHit?.keyName, "C")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyCmdTests/KeyFrameRegistryTests/testComputeFramesForSimpleGrid 2>&1 | tail -20`
Expected: FAIL — `KeyboardLayoutDescription` not found.

- [ ] **Step 3: Add KeyboardLayoutDescription and computeFrames to KeyFrameRegistry**

Add to `KeyCmd/View/MultiTouch/KeyFrameRegistry.swift`:

```swift
import SwiftUI

/// Describes the keyboard layout as a grid of key names with sizing metadata.
/// The touch container uses this to compute key frames without depending on SwiftUI layout.
struct KeyboardLayoutDescription {
    let rows: [[String]]
    let containerSize: CGSize
    let rowSpacing: CGFloat
    let keySpacing: CGFloat
    let padding: EdgeInsets
    /// Explicit heights for specific row indices. Rows not listed share remaining height equally.
    let fixedRowHeights: [CGFloat]
    /// Explicit widths for specific "rowKey" strings (e.g., "Space" → 200pt).
    let fixedKeyWidths: [String: CGFloat]

    init(
        rows: [[String]],
        containerSize: CGSize,
        rowSpacing: CGFloat,
        keySpacing: CGFloat,
        padding: EdgeInsets,
        fixedRowHeights: [CGFloat],
        fixedKeyWidths: [String: CGFloat]
    ) {
        self.rows = rows
        self.containerSize = containerSize
        self.rowSpacing = rowSpacing
        self.keySpacing = keySpacing
        self.padding = padding
        self.fixedRowHeights = fixedRowHeights
        self.fixedKeyWidths = fixedKeyWidths
    }
}

extension KeyFrameRegistry {
    /// Compute key frames from a layout description and register all keys.
    /// - Parameters:
    ///   - layout: The keyboard layout description.
    ///   - keyTypeResolver: Closure that maps a key name to its KeyType.
    func computeFrames(from layout: KeyboardLayoutDescription, keyTypeResolver: (String) -> KeyType) {
        clear()

        let contentOriginX = layout.padding.leading
        let contentOriginY = layout.padding.top
        let contentWidth = layout.containerSize.width - layout.padding.leading - layout.padding.trailing
        let contentHeight = layout.containerSize.height - layout.padding.top - layout.padding.bottom

        // Compute row heights
        let totalRowSpacing = CGFloat(max(0, layout.rows.count - 1)) * layout.rowSpacing
        let fixedHeightSum = layout.fixedRowHeights.reduce(0, +)
        let flexibleRowCount = layout.rows.count - layout.fixedRowHeights.count
        let flexibleRowHeight: CGFloat
        if flexibleRowCount > 0 {
            flexibleRowHeight = max(0, contentHeight - totalRowSpacing - fixedHeightSum) / CGFloat(flexibleRowCount)
        } else {
            flexibleRowHeight = 0
        }

        var currentY = contentOriginY
        for (rowIdx, row) in layout.rows.enumerated() {
            let rowHeight: CGFloat
            if rowIdx < layout.fixedRowHeights.count {
                rowHeight = layout.fixedRowHeights[rowIdx]
            } else {
                rowHeight = flexibleRowHeight
            }

            // Compute key widths for this row
            let totalKeySpacing = CGFloat(max(0, row.count - 1)) * layout.keySpacing
            var fixedWidthSum: CGFloat = 0
            var flexibleKeyCount = 0
            for keyName in row {
                if let fixedWidth = layout.fixedKeyWidths[keyName] {
                    fixedWidthSum += fixedWidth
                } else {
                    flexibleKeyCount += 1
                }
            }
            let flexibleKeyWidth: CGFloat
            if flexibleKeyCount > 0 {
                flexibleKeyWidth = max(0, contentWidth - totalKeySpacing - fixedWidthSum) / CGFloat(flexibleKeyCount)
            } else {
                flexibleKeyWidth = 0
            }

            var currentX = contentOriginX
            for keyName in row {
                let keyWidth: CGFloat
                if let fixedWidth = layout.fixedKeyWidths[keyName] {
                    keyWidth = fixedWidth
                } else {
                    keyWidth = flexibleKeyWidth
                }

                let frame = CGRect(x: currentX, y: currentY, width: keyWidth, height: rowHeight)
                let keyType = keyTypeResolver(keyName)
                register(KeyRegistration(
                    keyId: "\(rowIdx)-\(keyName)",
                    keyName: keyName,
                    keyType: keyType,
                    frame: frame
                ))

                currentX += keyWidth + layout.keySpacing
            }

            currentY += rowHeight + layout.rowSpacing
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyCmdTests/KeyFrameRegistryTests 2>&1 | tail -20`
Expected: All 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add KeyCmd/View/MultiTouch/KeyFrameRegistry.swift KeyCmdTests/KeyFrameRegistryTests.swift
git commit -m "feat: add keyboard layout frame computation

KeyboardLayoutDescription defines the grid structure and sizing.
KeyFrameRegistry.computeFrames() calculates key positions from
container size, spacing, padding, and fixed dimensions."
```

---

### Task 3: Touch Tracker

**Files:**
- Create: `KeyCmd/View/MultiTouch/TouchTracker.swift`
- Test: `KeyCmdTests/TouchTrackerTests.swift`

- [ ] **Step 1: Create test file with failing tests**

```swift
// KeyCmdTests/TouchTrackerTests.swift
import XCTest
@testable import KeyMod

final class TouchTrackerTests: XCTestCase {

    func testInitialActiveCountIsZero() {
        let tracker = TouchTracker()
        XCTAssertEqual(tracker.activeTouchCount, 0)
    }

    func testRegisterTouchFiresPress() {
        let tracker = TouchTracker()
        var pressedKeys: [String] = []
        tracker.onPress = { keyName, _ in pressedKeys.append(keyName) }

        let touch = MockTouch(id: 1)
        let reg = KeyRegistration(keyId: "tab", keyName: "Tab", keyType: .regular, frame: .zero)
        tracker.touchBegan(touch, key: reg)

        XCTAssertEqual(tracker.activeTouchCount, 1)
        XCTAssertEqual(pressedKeys, ["Tab"])
    }

    func testUnregisterTouchFiresRelease() {
        let tracker = TouchTracker()
        var releasedKeys: [String] = []
        tracker.onRelease = { keyName, _ in releasedKeys.append(keyName) }

        let touch = MockTouch(id: 1)
        let reg = KeyRegistration(keyId: "tab", keyName: "Tab", keyType: .regular, frame: .zero)
        tracker.touchBegan(touch, key: reg)
        tracker.touchEnded(touch)

        XCTAssertEqual(tracker.activeTouchCount, 0)
        XCTAssertEqual(releasedKeys, ["Tab"])
    }

    func testMultipleSimultaneousTouches() {
        let tracker = TouchTracker()
        var pressedKeys: [String] = []
        var releasedKeys: [String] = []
        tracker.onPress = { keyName, _ in pressedKeys.append(keyName) }
        tracker.onRelease = { keyName, _ in releasedKeys.append(keyName) }

        let touch1 = MockTouch(id: 1)
        let touch2 = MockTouch(id: 2)
        let cmdReg = KeyRegistration(keyId: "cmd", keyName: "Cmd", keyType: .modifier, frame: .zero)
        let tabReg = KeyRegistration(keyId: "tab", keyName: "Tab", keyType: .regular, frame: .zero)

        tracker.touchBegan(touch1, key: cmdReg)
        tracker.touchBegan(touch2, key: tabReg)

        XCTAssertEqual(tracker.activeTouchCount, 2)
        XCTAssertEqual(pressedKeys, ["Cmd", "Tab"])

        // Release Tab while Cmd still held
        tracker.touchEnded(touch2)
        XCTAssertEqual(tracker.activeTouchCount, 1)
        XCTAssertEqual(releasedKeys, ["Tab"])

        // Release Cmd
        tracker.touchEnded(touch1)
        XCTAssertEqual(tracker.activeTouchCount, 0)
        XCTAssertEqual(releasedKeys, ["Tab", "Cmd"])
    }

    func testTouchMovedFiresMoved() {
        let tracker = TouchTracker()
        var movedPoints: [CGPoint] = []
        tracker.onMoved = { point, _ in movedPoints.append(point) }

        let touch = MockTouch(id: 1)
        let reg = KeyRegistration(keyId: "cmd", keyName: "Cmd", keyType: .modifier, frame: .zero)
        tracker.touchBegan(touch, key: reg)
        tracker.touchMoved(touch, point: CGPoint(x: 10, y: 20))

        XCTAssertEqual(movedPoints.count, 1)
        XCTAssertEqual(movedPoints[0], CGPoint(x: 10, y: 20))
    }

    func testCancelAllTouches() {
        let tracker = TouchTracker()
        var releasedKeys: [String] = []
        tracker.onRelease = { keyName, _ in releasedKeys.append(keyName) }

        let touch1 = MockTouch(id: 1)
        let touch2 = MockTouch(id: 2)
        let cmdReg = KeyRegistration(keyId: "cmd", keyName: "Cmd", keyType: .modifier, frame: .zero)
        let tabReg = KeyRegistration(keyId: "tab", keyName: "Tab", keyType: .regular, frame: .zero)

        tracker.touchBegan(touch1, key: cmdReg)
        tracker.touchBegan(touch2, key: tabReg)
        tracker.cancelAll()

        XCTAssertEqual(tracker.activeTouchCount, 0)
        XCTAssertEqual(Set(releasedKeys), ["Cmd", "Tab"])
    }

    func testEndingUnknownTouchDoesNothing() {
        let tracker = TouchTracker()
        var releasedKeys: [String] = []
        tracker.onRelease = { keyName, _ in releasedKeys.append(keyName) }

        let unknownTouch = MockTouch(id: 999)
        tracker.touchEnded(unknownTouch)

        XCTAssertEqual(tracker.activeTouchCount, 0)
        XCTAssertTrue(releasedKeys.isEmpty)
    }
}

// MARK: - Mock Touch for testing

/// Lightweight stand-in for UITouch in unit tests.
/// Uses an integer ID for identity comparison (matching UITouch behavior).
final class MockTouch: Hashable {
    let id: Int
    init(id: Int) { self.id = id }

    static func == (lhs: MockTouch, rhs: MockTouch) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyCmdTests/TouchTrackerTests 2>&1 | tail -20`
Expected: FAIL — `TouchTracker` not found.

- [ ] **Step 3: Create TouchTracker**

```swift
// KeyCmd/View/MultiTouch/TouchTracker.swift
import UIKit

/// Tracks active touches and maps each to a key. Fires callbacks on press/release/move.
///
/// The generic parameter `Touch` allows unit testing with a mock type instead of `UITouch`.
/// In production, `Touch` is `UITouch`. The only requirement is `Hashable` identity.
final class TouchTracker<Touch: Hashable> {

    /// Called when a touch begins on a key. (keyName, keyType)
    var onPress: ((String, KeyType) -> Void)?
    /// Called when a touch ends or is cancelled. (keyName, keyType)
    var onRelease: ((String, KeyType) -> Void)?
    /// Called when a touch moves. (point, keyName)
    var onMoved: ((CGPoint, String) -> Void)?

    /// Maps each active touch to its current key registration.
    private var activeTouches: [Touch: KeyRegistration] = [:]

    /// Number of currently tracked touches.
    var activeTouchCount: Int { activeTouches.count }

    func touchBegan(_ touch: Touch, key: KeyRegistration) {
        activeTouches[touch] = key
        onPress?(key.keyName, key.keyType)
    }

    func touchMoved(_ touch: Touch, point: CGPoint) {
        guard let reg = activeTouches[touch] else { return }
        onMoved?(point, reg.keyName)
    }

    func touchEnded(_ touch: Touch) {
        guard let reg = activeTouches.removeValue(forKey: touch) else { return }
        onRelease?(reg.keyName, reg.keyType)
    }

    /// Cancel all active touches, firing onRelease for each.
    func cancelAll() {
        let allTouches = activeTouches
        activeTouches.removeAll()
        for (_, reg) in allTouches {
            onRelease?(reg.keyName, reg.keyType)
        }
    }

    /// Get the key registration for a specific touch.
    func key(for touch: Touch) -> KeyRegistration? {
        activeTouches[touch]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:KeyCmdTests/TouchTrackerTests 2>&1 | tail -20`
Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add KeyCmd/View/MultiTouch/TouchTracker.swift KeyCmdTests/TouchTrackerTests.swift
git commit -m "feat: add touch tracker for multi-touch key state

TouchTracker maps each active touch to a key registration and fires
press/release/move callbacks. Supports cancelAll for system gesture
interruption handling."
```

---

### Task 4: MultiTouchKeyboardContainerView (UIKit)

**Files:**
- Create: `KeyCmd/View/MultiTouch/MultiTouchKeyboardContainerView.swift`

- [ ] **Step 1: Create the UIKit view that handles multi-touch**

```swift
// KeyCmd/View/MultiTouch/MultiTouchKeyboardContainerView.swift
import UIKit

/// UIKit view that handles multi-touch for the keyboard.
/// Overrides touchesBegan/Moved/Ended/Cancelled to dispatch key events.
/// Must have `isMultipleTouchEnabled = true`.
final class MultiTouchKeyboardContainerView: UIView {

    let registry = KeyFrameRegistry()
    private let tracker = TouchTracker<UITouch>()

    /// Called when a key is pressed. (keyName, keyType)
    var onPress: ((String, KeyType) -> Void)?
    /// Called when a key is released. (keyName, keyType)
    var onRelease: ((String, KeyType) -> Void)?
    /// Called when a touch moves. (point, keyName)
    var onMoved: ((CGPoint, String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isUserInteractionEnabled = true

        tracker.onPress = { [weak self] keyName, keyType in
            self?.onPress?(keyName, keyType)
        }
        tracker.onRelease = { [weak self] keyName, keyType in
            self?.onRelease?(keyName, keyType)
        }
        tracker.onMoved = { [weak self] point, keyName in
            self?.onMoved?(point, keyName)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if let key = registry.hitTest(point) {
                tracker.touchBegan(touch, key: key)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            tracker.touchMoved(touch, point: point)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            tracker.touchEnded(touch)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            tracker.touchEnded(touch) // treat cancellation same as release
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add KeyCmd/View/MultiTouch/MultiTouchKeyboardContainerView.swift
git commit -m "feat: add UIKit multi-touch keyboard container view

MultiTouchKeyboardContainerView is a UIView subclass with
isMultipleTouchEnabled=true that dispatches multi-touch events
through a TouchTracker to onPress/onRelease/onMoved callbacks."
```

---

### Task 5: UIViewRepresentable Bridge

**Files:**
- Create: `KeyCmd/View/MultiTouch/MultiTouchKeyboardContainer.swift`

- [ ] **Step 1: Create the SwiftUI bridge**

```swift
// KeyCmd/View/MultiTouch/MultiTouchKeyboardContainer.swift
import SwiftUI

/// SwiftUI wrapper for MultiTouchKeyboardContainerView.
/// Exposes the key registry and event callbacks to SwiftUI views.
struct MultiTouchKeyboardContainer: UIViewRepresentable {

    /// Layout description for computing key frames.
    let layout: KeyboardLayoutDescription
    /// Maps key names to their KeyType.
    let keyTypeResolver: (String) -> KeyType
    /// Called when a key is pressed.
    let onPress: (String, KeyType) -> Void
    /// Called when a key is released.
    let onRelease: (String, KeyType) -> Void
    /// Called when a touch moves (for slide-to-lock detection).
    let onMoved: (CGPoint, String) -> Void

    func makeUIView(context: Context) -> MultiTouchKeyboardContainerView {
        let view = MultiTouchKeyboardContainerView()
        view.onPress = onPress
        view.onRelease = onRelease
        view.onMoved = onMoved
        view.registry.computeFrames(from: layout, keyTypeResolver: keyTypeResolver)
        return view
    }

    func updateUIView(_ uiView: MultiTouchKeyboardContainerView, context: Context) {
        // Update callbacks (they may capture changing state)
        uiView.onPress = onPress
        uiView.onRelease = onRelease
        uiView.onMoved = onMoved
        // Recompute frames when layout changes (rotation, resize)
        uiView.registry.computeFrames(from: layout, keyTypeResolver: keyTypeResolver)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add KeyCmd/View/MultiTouch/MultiTouchKeyboardContainer.swift
git commit -m "feat: add SwiftUI bridge for multi-touch keyboard container

MultiTouchKeyboardContainer is a UIViewRepresentable that wraps
MultiTouchKeyboardContainerView and exposes layout + callbacks."
```

---

### Task 6: Visual-Only Key Views

**Files:**
- Create: `KeyCmd/View/MultiTouch/VisualKeyViews.swift`

These views replace `ModifierKeyButton` and `KeyPressButton` in the Basic keyboard's visual layer. They render the same appearance but do NOT handle touches — the `MultiTouchKeyboardContainer` overlay handles all touch events.

- [ ] **Step 1: Create visual-only key views**

```swift
// KeyCmd/View/MultiTouch/VisualKeyViews.swift
import SwiftUI

/// Visual-only modifier key view. Renders the key appearance including
/// pressed/locked state but does NOT handle touches.
struct ModifierKeyVisual: View {
    let key: String
    let displayText: String
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var themeManager: ThemeManager
    let isPressed: Bool
    let isLocked: Bool

    var body: some View {
        Text(displayText)
            .font(.system(size: 12, weight: .bold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isPressed || isLocked ? themeManager.accentColor : Self.functionKeyBg)
            .cornerRadius(6)
            .foregroundColor(isPressed || isLocked ? Self.keyLabelPressed : Self.keyLabelIdle)
    }

    static let functionKeyBg = Color(.secondarySystemBackground)
    static let keyLabelPressed = Color.white
    static let keyLabelIdle = Color.primary
}

/// Visual-only regular key view. Renders the key appearance including
/// pressed state but does NOT handle touches.
struct KeyVisual: View {
    let content: AnyView
    let isPressed: Bool
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isPressed ? themeManager.accentColor : Color(.secondarySystemBackground))
            .cornerRadius(6)
            .foregroundColor(isPressed ? Color.white : Color.primary)
    }
}
```

Note: These visual views are intentionally simplified. The actual visual rendering will be wired in Task 7 where we integrate into `BasicKeyboardMouseView`. The views above establish the interface; the actual visual content (dual labels, icons, etc.) will reuse existing helper functions from `BasicKeyboardMouseView`.

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add KeyCmd/View/MultiTouch/VisualKeyViews.swift
git commit -m "feat: add visual-only key views for multi-touch keyboard

ModifierKeyVisual and KeyVisual render key appearance without touch
handling. The multi-touch container overlay handles all input."
```

---

### Task 7: Integration into BasicKeyboardMouseView

**Files:**
- Modify: `KeyCmd/View/BasicKeyboardMouseView.swift`

This is the largest task. We wrap the existing keyboard layout in a `ZStack` and add the `MultiTouchKeyboardContainer` overlay. We also add a method to build the `KeyboardLayoutDescription` from the existing row data.

- [ ] **Step 1: Add helper to build KeyboardLayoutDescription from current layout**

Add a new method to `BasicKeyboardMouseView`:

```swift
    /// Build a KeyboardLayoutDescription from the current keyboard layout and container size.
    /// This mirrors the SwiftUI layout math so the touch container's key frames match the visual positions.
    private func buildLayoutDescription(for size: CGSize, isWindowsLayout: Bool) -> KeyboardLayoutDescription {
        let rows: [[String]]
        let fixedRowHeights: [CGFloat]
        let fixedKeyWidths: [String: CGFloat]

        if isWindowsLayout {
            rows = [windowsFRow, windowsNumberRow, windowsRow3, windowsRow4, windowsRow5,
                    ["Ctrl", "Win", "Alt", "Space", "Alt", "Ctrl", "Left", "Up", "Down", "Right"]]
            // Rows 1-2 at half height, rows 3-6 equal
            let totalSpacing = CGFloat(5) * 6 // 5 gaps × 6pt
            let remaining = max(0, size.height - totalSpacing - 8) // 8pt top padding
            let topH = remaining / 10
            fixedRowHeights = [topH, topH] // first two rows fixed
            fixedKeyWidths = ["Space": 200]
        } else {
            // Mac layout — same row structure but different bottom row
            rows = [windowsFRow, windowsNumberRow, windowsRow3, windowsRow4, windowsRow5,
                    ["Ctrl", "Option", "Cmd", "Space", "Cmd", "Option", "Ctrl", "Up", "Down"]]
            let totalSpacing = CGFloat(5) * 6
            let remaining = max(0, size.height - totalSpacing - 8)
            let topH = remaining / 10
            fixedRowHeights = [topH, topH]
            fixedKeyWidths = ["Space": 200]
        }

        return KeyboardLayoutDescription(
            rows: rows,
            containerSize: size,
            rowSpacing: 6,
            keySpacing: 3,
            padding: EdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 0),
            fixedRowHeights: fixedRowHeights,
            fixedKeyWidths: fixedKeyWidths
        )
    }

    /// Map key names to their KeyType for the touch container.
    private func keyType(for keyName: String) -> KeyType {
        let modifiers: Set<String> = ["Ctrl", "Alt", "Cmd", "Win", "Option", "Super", "Shift"]
        let specials: Set<String> = ["Caps"]
        if modifiers.contains(keyName) { return .modifier }
        if specials.contains(keyName) { return .special }
        return .regular
    }
```

- [ ] **Step 2: Add touch event handlers**

Add methods that the touch container calls:

```swift
    // MARK: - Multi-touch event handlers

    private func handleMultiTouchPress(keyName: String, keyType: KeyType) {
        switch keyType {
        case .modifier:
            let prefs = KmBasicKeyboardPrefs.shared
            switch prefs.modifierBehavior {
            case .sticky:
                break // Toggle fires on release
            case .momentaryChord:
                if prefs.chordSustainHid {
                    keyboardManager.handleKeyDown(keyName)
                } else {
                    keyboardManager.addModifierTrackedOnly(keyName)
                }
            }
        case .regular:
            let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
            let effectiveKey = keyName == "Esc" ? "Escape" : keyName
            if repeatMode {
                keyboardManager.startKeyRepeat(effectiveKey)
            } else {
                keyboardManager.handleKeyDown(effectiveKey)
            }
        case .special:
            keyboardManager.handleSpecialKey(keyName)
        }
    }

    private func handleMultiTouchRelease(keyName: String, keyType: KeyType) {
        switch keyType {
        case .modifier:
            let prefs = KmBasicKeyboardPrefs.shared
            switch prefs.modifierBehavior {
            case .sticky:
                // Tap-toggle
                if keyboardManager.lockedModifiers.contains(keyName) {
                    keyboardManager.unlockModifier(keyName)
                } else {
                    keyboardManager.lockModifier(keyName)
                }
            case .momentaryChord:
                keyboardManager.handleKeyUp(keyName)
            }
        case .regular:
            let repeatMode = KmBasicKeyboardPrefs.shared.isLongPressRepeatMode
            let effectiveKey = keyName == "Esc" ? "Escape" : keyName
            if repeatMode {
                keyboardManager.stopKeyRepeat()
            } else {
                keyboardManager.handleKeyUp(effectiveKey)
            }
        case .special:
            break // Caps has no release behavior
        }
    }

    private func handleMultiTouchMoved(point: CGPoint, keyName: String) {
        // Slide-to-lock detection for modifier keys in momentary-chord mode
        // This is a placeholder — full implementation needs lock icon position
        // which depends on the visual layout of each modifier key.
    }
```

- [ ] **Step 3: Modify the keyboard layout views to add the touch overlay**

In both `windowsKeyboardLayout` and `macKeyboardLayout`, wrap the VStack in a ZStack and add the overlay. The pattern is:

```swift
    private var windowsKeyboardLayout: some View {
        GeometryReader { geo in
            ZStack {
                // Existing VStack keyboard layout (unchanged, but ModifierKeyButton/KeyPressButton
                // will be replaced with visual-only views in a follow-up commit)
                existingKeyboardVStack(geo: geo)

                // Multi-touch overlay
                MultiTouchKeyboardContainer(
                    layout: buildLayoutDescription(for: geo.size, isWindowsLayout: true),
                    keyTypeResolver: keyType(for:),
                    onPress: { keyName, keyType in
                        handleMultiTouchPress(keyName: keyName, keyType: keyType)
                    },
                    onRelease: { keyName, keyType in
                        handleMultiTouchRelease(keyName: keyName, keyType: keyType)
                    },
                    onMoved: { point, keyName in
                        handleMultiTouchMoved(point: point, keyName: keyName)
                    }
                )
            }
        }
    }
```

Apply the same pattern to `macKeyboardLayout` with `isWindowsLayout: false`.

**Important:** In this step, keep the existing `ModifierKeyButton` and `KeyPressButton` in the visual layer. Both the old per-key touch handlers AND the new unified container will fire. This is intentional — we verify the unified container works by checking that touch events arrive correctly. In the next commit, we disable the old touch handlers.

- [ ] **Step 4: Build and run on device, verify basic key presses still work**

Build on a physical iPhone (BLE requires real device). Verify:
- Single key presses work (type "hello")
- Modifier + key combos work (Cmd+C)
- The multi-touch container overlay doesn't block visual rendering

- [ ] **Step 5: Commit (intermediate — both touch layers active)**

```bash
git add KeyCmd/View/BasicKeyboardMouseView.swift
git commit -m "feat: add multi-touch container overlay to Basic keyboard

The unified MultiTouchKeyboardContainer now overlays the keyboard.
Both old per-key handlers and new container are active temporarily
for verification."
```

---

### Task 8: Disable Old Per-Key Touch Handlers

**Files:**
- Modify: `KeyCmd/View/BasicKeyboardMouseView.swift`

Now that the unified container handles touches, disable the old `PressDetectorView`-based handlers in `ModifierKeyButton` and `KeyPressButton` when used from the Basic keyboard layout. The simplest approach: make the old buttons no-op their touch handlers by passing empty closures, and use the visual-only rendering.

Actually, a cleaner approach: since the visual layer in the Basic keyboard now has the touch overlay, we replace `ModifierKeyButton` and `KeyPressButton` calls in `windowsKeyButton()` and related functions with visual-only views that don't create `PressDetectorView`.

- [ ] **Step 1: Create visual-only wrapper functions**

In `BasicKeyboardMouseView`, add visual-only versions of the key button functions. These reuse the existing visual rendering code but skip `PressDetectorView`:

```swift
    /// Visual-only version of windowsKeyButton — no touch handling.
    /// Touch events come from the MultiTouchKeyboardContainer overlay.
    @ViewBuilder
    private func windowsKeyVisualOnly(key: String) -> some View {
        let keyLabel = windowsLabelOnKey(for: key)
        let modifierKeys: Set<String> = ["Ctrl", "Alt", "Cmd", "Win", "Option", "Super", "Shift"]
        let isCapsActive = key == "Caps" && keyboardManager.capsLockActive
        let isModifier = modifierKeys.contains(key)

        // For visual-only, we track pressed state from keyboardManager
        let isPressed = isModifier
            ? keyboardManager.activeModifiers.contains(key) || keyboardManager.lockedModifiers.contains(key)
            : keyboardManager.pressedKeys.contains(key == "Esc" ? "Escape" : key)

        Group {
            if isModifier || key == "Caps" {
                Text(keyLabel)
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background((isPressed || isCapsActive) ? themeManager.accentColor : Self.functionKeyBg)
                    .cornerRadius(6)
                    .foregroundColor((isPressed || isCapsActive) ? Self.keyLabelPressed : Self.keyLabelIdle)
            } else {
                windowsKeyContent(key: key, displayText: windowsDisplayValue(for: key))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isPressed ? themeManager.accentColor : Self.functionKeyBg)
                    .cornerRadius(6)
                    .foregroundColor(isPressed ? Self.keyIconPressed : Self.keyIconIdle)
            }
        }
    }
```

- [ ] **Step 2: Replace windowsKeyButton calls in the layout functions**

In `windowsKeyboardLayout` (and `macKeyboardLayout`), replace all `windowsKeyButton(key:)` calls with `windowsKeyVisualOnly(key:)`. Also replace direct `KeyPressButton` and `ModifierKeyButton` usage in the bottom row with visual-only equivalents.

- [ ] **Step 3: Build and test on device**

Build on a physical iPhone. Verify:
- Visual appearance is identical
- Single key presses work (the unified container dispatches them)
- **Cmd+Tab now works**: hold Cmd, press Tab — Cmd stays held

- [ ] **Step 4: Commit**

```bash
git add KeyCmd/View/BasicKeyboardMouseView.swift
git commit -m "feat: replace per-key touch handlers with unified container in Basic keyboard

ModifierKeyButton and KeyPressButton are replaced with visual-only views
in the Basic keyboard layout. All touch events are handled by the
MultiTouchKeyboardContainer overlay, fixing the Cmd+Tab multi-touch issue."
```

---

### Task 9: Handle Layout Updates on Rotation/Resize

**Files:**
- Modify: `KeyCmd/View/BasicKeyboardMouseView.swift`

The `MultiTouchKeyboardContainer`'s `updateUIView` already recomputes frames from the layout description. Since `GeometryReader` provides the new size on rotation, the layout description will update, triggering `updateUIView` and recomputing frames. We just need to verify this works correctly.

- [ ] **Step 1: Verify that GeometryReader + MultiTouchKeyboardContainer recompute on rotation**

The `GeometryReader` passes `geo.size` to `buildLayoutDescription`. When rotation changes the size, SwiftUI re-evaluates the body, creating a new `KeyboardLayoutDescription` with the new size. `MultiTouchKeyboardContainer.updateUIView` detects the new layout and calls `computeFrames`. This should work automatically.

- [ ] **Step 2: Build and test rotation on device**

Build on a physical iPhone. Verify:
- Rotate device — keyboard layout adjusts
- After rotation, all keys still respond correctly to touch
- Multi-touch (Cmd+Tab) still works after rotation

- [ ] **Step 3: Commit (if any adjustments needed)**

```bash
git add KeyCmd/View/BasicKeyboardMouseView.swift
git commit -m "fix: ensure multi-touch container updates key frames on rotation"
```

---

### Task 10: Preserve Slide-to-Lock for Modifier Keys

**Files:**
- Modify: `KeyCmd/View/MultiTouch/MultiTouchKeyboardContainerView.swift`
- Modify: `KeyCmd/View/BasicKeyboardMouseView.swift`

The slide-to-lock feature requires detecting when a finger on a modifier key moves upward past a threshold. In the old code, `ModifierKeyButton` handled this via `onMoved` and a lock icon. We need to replicate this in the unified container.

For the initial implementation, slide-to-lock can be deferred — the core fix (Cmd+Tab multi-touch) works without it. Users can still use sticky mode or lock modifiers via the existing toggle. The slide-to-lock is a polish feature.

- [ ] **Step 1: Verify basic functionality without slide-to-lock**

Build and test on device:
- Momentary-chord mode: hold Cmd + press Tab cycles apps
- Sticky mode: tap Cmd locks it, tap again unlocks
- All key presses and releases work correctly

- [ ] **Step 2: Commit slide-to-lock as follow-up (if implemented)**

```bash
git add KeyCmd/View/MultiTouch/ KeyCmd/View/BasicKeyboardMouseView.swift
git commit -m "feat: add slide-to-lock support in multi-touch container"
```

---

### Task 11: Integration Testing and Edge Cases

**Files:**
- Modify: `KeyCmd/View/BasicKeyboardMouseView.swift`

- [ ] **Step 1: Test edge case — touch cancelled by system gesture**

Build on device. Test:
- Start holding Cmd, then swipe from screen edge (system back gesture)
- Verify Cmd is released (not stuck in pressed state)
- Verify `activeModifiers` is cleaned up

- [ ] **Step 2: Test edge case — multiple fingers on same key**

Build on device. Test:
- Place two fingers on the same key
- Lift one finger — key should stay pressed
- Lift second finger — key should release

- [ ] **Step 3: Test edge case — finger slides between keys**

Build on device. Test:
- Press a key, slide finger to an adjacent key
- First key should release, second key should press

- [ ] **Step 4: Test all keyboard layouts**

Build on device. Test in both orientations:
- Windows layout (all 6 rows)
- Mac layout (all 6 rows)
- Linux layout (same as Windows)
- Original landscape layout

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "test: verify multi-touch keyboard edge cases

Tested: system gesture cancellation, multi-finger same key,
finger slide between keys, all keyboard layouts and orientations."
```
