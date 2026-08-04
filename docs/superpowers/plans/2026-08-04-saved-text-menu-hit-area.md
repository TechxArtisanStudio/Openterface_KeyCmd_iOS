# Saved Text Menu Hit Area Expansion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the tap target of the three-dot (`ellipsis`) menu button in each saved text row to the Apple HIG standard 44×44pt.

**Architecture:** Add `.frame(width: 44, height: 44)` and `.contentShape(Rectangle())` modifiers to the Menu label's Image in `SavedTextRow`. The icon's visual size (15pt) stays unchanged; only the hit area grows.

**Tech Stack:** SwiftUI (iOS 16+), Swift

## Global Constraints

- Only modify the Menu label inside `SavedTextRow` struct in `KeyCmd/View/ComposeTextView.swift`
- Do not change the icon visual size (must remain 15pt)
- Do not change Menu functionality, menu items, or any other view behavior
- Do not change row layout, styling, or `.onTapGesture`

---

### Task 1: Expand ellipsis button tap target

**Files:**
- Modify: `KeyCmd/View/ComposeTextView.swift:745-749` (Menu label inside `SavedTextRow`)

**Interfaces:**
- Consumes: `SavedTextRow` struct, `Menu` with ellipsis label
- Produces: `SavedTextRow` with 44×44pt tap target on the ellipsis button

- [ ] **Step 1: Read the current Menu label**

Open `KeyCmd/View/ComposeTextView.swift` and read lines 745–749 to see the current Menu label:

```swift
} label: {
    Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.secondary)
}
```

- [ ] **Step 2: Add frame and contentShape modifiers**

Add `.frame(width: 44, height: 44)` and `.contentShape(Rectangle())` to the Image. The modified label becomes:

```swift
} label: {
    Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.secondary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
}
```

- [ ] **Step 3: Verify the build**

Build the project to confirm the change compiles:

```bash
xcodebuild -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Expected: Build succeeds with no errors.

- [ ] **Step 4: Manual verification**

Run the app in the simulator:
1. Navigate to KeyboardMouse Pro → Input page → Open saved text library (bookmark icon)
2. Verify each row shows the ⋯ button with a comfortably large tap area (~44×44pt)
3. Tap the ⋯ to confirm the menu still opens with Pin/Rename/Delete
4. Tap elsewhere on the row to confirm row selection still works

- [ ] **Step 5: Commit**

```bash
git add KeyCmd/View/ComposeTextView.swift
git commit -m "fix: expand ellipsis menu tap target to Apple HIG 44x44pt

Add .frame(width: 44, height: 44) and .contentShape(Rectangle()) to
the Menu label Image in SavedTextRow. The icon visual size stays 15pt;
only the hit area grows to the Apple HIG minimum.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

- [ ] **Step 6: Verify final state**

Read lines 745–751 of `ComposeTextView.swift` to confirm the final code matches:

```swift
} label: {
    Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.secondary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
}
```
