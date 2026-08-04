# Saved Text Row: Swipe-to-Menu Interaction Redesign

**Date:** 2026-08-04
**Status:** Draft
**Scope:** `KeyCmd/View/ComposeTextView.swift` — `SavedTextRow` only

---

## Summary

Replace the current swipe-to-reveal gesture on saved text rows with an always-visible three-dot menu button on the right side of each row. Tapping the button shows a popover menu with Pin/Unpin, Rename, and Delete actions.

## Problem

The current interaction uses `.swipeActions(edge: .trailing)` to reveal three actions (Pin, Rename, Delete). This is:
- Not discoverable — users may not know the swipe gesture exists
- Inconvenient — requires a swipe for every action
- Inconsistent with common iOS patterns where a menu button is always visible

## Solution

Add a persistent three-dot (`ellipsis`) button to the right of each row's title line. Tapping it opens a SwiftUI `Menu` popover with the three actions. Remove the `.swipeActions` modifier entirely.

## Design

### Row Layout

**Before:**
```
[pin] Title (left) ................. Dec 25 (right)
      Body preview text...
```

**After:**
```
[pin] Title (left) ...................... ⋯ (right)
      Dec 25 · Body preview text...
```

- Line 1: Optional pin icon + Title (left) ... three-dot button (right)
- Line 2: Date + " · " separator + body preview (combined into one line)

### Menu Behavior

- Icon: `Image(systemName: "ellipsis")`
- Presentation: SwiftUI `Menu` (popover on iPhone, native menu on iPad)
- Menu items:
  1. **Pin to Top** / **Unpin** — icon: `pin` / `pin.slash`
  2. **Rename** — icon: `pencil`
  3. **Delete** — icon: `trash`, destructive style (red text)
- The row's existing tap gesture (`onTapGesture` → `onSelect`) is unaffected

### Code Changes

**File:** `KeyCmd/View/ComposeTextView.swift`
**Struct:** `SavedTextRow` (lines 712–757)

1. **Remove** the `.swipeActions(edge: .trailing, allowsFullSwipe: false)` block (lines 735–747)
2. **Restructure** the first `HStack`:
   - Remove the date `Text` from the right side of line 1
   - Add a `Menu` with the three-dot button on the right side of line 1
3. **Restructure** the second line:
   - Prepend the date (using `Text(item.createdAt, style: .date)`) before the body preview, separated by `" · "`
4. **Keep** all existing callbacks (`onSelect`, `onDelete`, `onRename`, `onPin`) unchanged
5. **Keep** all existing visual styling (pin icon, title font, selection background) unchanged

### What Does NOT Change

- `SavedTextItem` model — no changes
- `SavedTextStore` — no changes to data, persistence, or operations
- `savedTextLibrarySheet` — toolbar and overall sheet structure unchanged
- `itemsSorted()`, `loadItem()`, `sendItem()`, `previewItem()` — no changes
- All action callbacks remain the same — only the UI trigger changes from swipe to menu button

## Non-Goals

- No changes to any other view or feature
- No animation changes beyond what SwiftUI `Menu` provides by default
- No new functionality — this is purely an interaction pattern change
