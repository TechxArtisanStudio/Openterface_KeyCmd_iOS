# Saved Text Row Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the swipe-to-reveal gesture in `SavedTextRow` with a persistent three-dot menu button that shows Pin/Rename/Delete actions in a popover.

**Architecture:** Modify the `SavedTextRow` struct in `ComposeTextView.swift` to remove `.swipeActions` and add a SwiftUI `Menu` with a three-dot button. Restructure the row layout: title and menu button on line 1, date and body preview combined on line 2.

**Tech Stack:** SwiftUI (iOS 16+), Swift

## Global Constraints

- Only modify `SavedTextRow` struct in `KeyCmd/View/ComposeTextView.swift`
- Do not modify `SavedTextItem` model, `SavedTextStore`, or any other views
- Keep all existing callbacks (`onSelect`, `onDelete`, `onRename`, `onPin`) unchanged
- Keep existing visual styling (pin icon, title font, selection background) unchanged
- Use SwiftUI `Menu` for popover presentation

---

### Task 1: Replace swipeActions with three-dot menu button

**Files:**
- Modify: `KeyCmd/View/ComposeTextView.swift:712-757` (`SavedTextRow` struct)

**Interfaces:**
- Consumes: `SavedTextItem` model, `onSelect`, `onDelete`, `onRename`, `onPin` callbacks
- Produces: `SavedTextRow` view with menu button instead of swipe actions

- [ ] **Step 1: Read the current SavedTextRow implementation**

Open `KeyCmd/View/ComposeTextView.swift` and read lines 712–757 to understand the current structure.

Current structure:
```swift
struct SavedTextRow: View {
    let item: SavedTextItem
    let isSelected: Bool
    let onSelect: (SavedTextItem) -> Void
    let onDelete: (UUID) -> Void
    let onRename: (SavedTextItem) -> Void
    let onPin: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if item.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundColor(.orange)
                }
                Text(item.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(item.createdAt, style: .date).font(.caption2).foregroundColor(.secondary)
            }
            Text(bodyPreview).font(.system(size: 13)).foregroundColor(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        .onTapGesture { onSelect(item) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDelete(item.id) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { onRename(item) } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
            Button { onPin(item.id) } label: {
                Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
    }

    private var bodyPreview: String {
        let titlePrefix = String(item.text.prefix(item.title.count))
        if item.title == titlePrefix {
            return String(item.text.dropFirst(min(item.title.count, item.text.count)))
        }
        return item.text
    }
}
```

- [ ] **Step 2: Restructure the first HStack**

Replace the first `HStack` (lines 722–729) to:
1. Keep the pin icon (if pinned)
2. Keep the title
3. Remove the date from line 1
4. Add a `Menu` with three-dot button after the `Spacer()`

New first HStack:
```swift
HStack {
    if item.pinned {
        Image(systemName: "pin.fill").font(.caption2).foregroundColor(.orange)
    }
    Text(item.title).font(.system(size: 15, weight: .semibold))
    Spacer()
    Menu {
        Button {
            onPin(item.id)
        } label: {
            Label(item.pinned ? "Unpin" : "Pin to Top",
                  systemImage: item.pinned ? "pin.slash" : "pin")
        }
        Button {
            onRename(item)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button(role: .destructive) {
            onDelete(item.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    } label: {
        Image(systemName: "ellipsis")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.secondary)
    }
}
```

- [ ] **Step 3: Restructure the second line**

Replace the second line (line 730) to combine date and body preview:

```swift
HStack(spacing: 4) {
    Text(item.createdAt, style: .date)
        .font(.caption2)
        .foregroundColor(.secondary)
    Text("· \(bodyPreview)")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
        .lineLimit(1)
}
```

- [ ] **Step 4: Remove the swipeActions modifier**

Delete the entire `.swipeActions(edge: .trailing, allowsFullSwipe: false)` block (lines 735–747).

- [ ] **Step 5: Verify the complete modified struct**

The complete modified `SavedTextRow` should look like:

```swift
struct SavedTextRow: View {
    let item: SavedTextItem
    let isSelected: Bool
    let onSelect: (SavedTextItem) -> Void
    let onDelete: (UUID) -> Void
    let onRename: (SavedTextItem) -> Void
    let onPin: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if item.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundColor(.orange)
                }
                Text(item.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Menu {
                    Button {
                        onPin(item.id)
                    } label: {
                        Label(item.pinned ? "Unpin" : "Pin to Top",
                              systemImage: item.pinned ? "pin.slash" : "pin")
                    }
                    Button {
                        onRename(item)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete(item.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 4) {
                Text(item.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("· \(bodyPreview)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        .onTapGesture { onSelect(item) }
    }

    private var bodyPreview: String {
        let titlePrefix = String(item.text.prefix(item.title.count))
        if item.title == titlePrefix {
            return String(item.text.dropFirst(min(item.title.count, item.text.count)))
        }
        return item.text
    }
}
```

- [ ] **Step 6: Build the project**

Run: Open Xcode and build the project (⌘B), or use command line:
```bash
xcodebuild -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Expected: Build succeeds with no errors.

- [ ] **Step 7: Manual testing**

1. Run the app in the iOS Simulator or on a device
2. Navigate to KeyboardMouse Pro → Input page → Open the saved text library (bookmark icon)
3. Verify:
   - Each row shows: [pin icon (if pinned)] Title (left) ... ⋯ (right)
   - Second line shows: Date · Body preview
   - Tapping the ⋯ button opens a popover menu with three options:
     - Pin to Top / Unpin (with pin/pin.slash icon)
     - Rename (with pencil icon)
     - Delete (with trash icon, red text)
   - Each menu action works correctly
   - Tapping the row (not the menu) still selects it
   - Swipe gestures no longer reveal any actions
4. Test on both iPhone and iPad if possible (menu presentation differs)

- [ ] **Step 8: Commit the changes**

```bash
git add KeyCmd/View/ComposeTextView.swift
git commit -m "feat: replace swipe actions with three-dot menu in saved text rows

Replace left-swipe gesture with a persistent ellipsis button on the right
side of each saved text row. Tapping shows a popover menu with Pin/Rename/
Delete actions. Restructure row layout: title + menu on line 1, date +
preview on line 2.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

- [ ] **Step 9: Verify final state**

Read the modified `SavedTextRow` struct one more time to confirm:
- No `.swipeActions` modifier
- Menu with three-dot button present
- Layout matches spec: Line 1 = [pin] Title + ⋯, Line 2 = Date · Preview
- All callbacks unchanged
