# Saved Text Row Menu: Hit Area Expansion

**Date:** 2026-08-04
**Status:** Draft
**Scope:** `KeyCmd/View/ComposeTextView.swift` — `SavedTextRow` Menu label only

---

## Summary

Expand the tap target of the three-dot (`ellipsis`) menu button in each saved text row to the Apple HIG standard 44×44pt. The icon's visual size stays 15pt; only the hit area grows.

## Problem

After the swipe-to-menu refactor, the `ellipsis` icon (15pt) is the only way to access Pin/Rename/Delete on each row. Its tap target is approximately 15×15pt — far below Apple's Human Interface Guidelines minimum of 44×44pt. Users report difficulty tapping it.

## Solution

Add `.frame(width: 44, height: 44)` and `.contentShape(Rectangle())` to the Menu label's Image, expanding its hit area without changing its visual appearance.

## Design

### Code Change

**File:** `KeyCmd/View/ComposeTextView.swift`
**Struct:** `SavedTextRow`, Menu label (lines 745–749)

```swift
// Before
} label: {
    Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.secondary)
}

// After
} label: {
    Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.secondary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
}
```

### Behavior

- Tap target: 44×44pt (Apple HIG standard)
- Visual appearance: unchanged (15pt ellipsis icon)
- Menu functionality: unchanged
- Row selection (`.onTapGesture`): unaffected — Menu consumes taps within its own 44×44 frame
- Layout: unaffected — the frame occupies the same space after the `Spacer()`

### What Does NOT Change

- `SavedTextItem` model — no changes
- `SavedTextStore` — no changes
- Menu items (Pin/Rename/Delete) — no changes
- Row layout, pin icon, title, date, preview — no changes
- `.onTapGesture` row selection — no changes

## Non-Goals

- No visual background or affordance for the button (no circle, no color change)
- No changes to any other view or interaction
- No change to the icon size itself
