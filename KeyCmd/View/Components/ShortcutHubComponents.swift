import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shortcut Display Style

enum ShortcutDisplayStyle { case list, card }

// MARK: - ShortcutCardView

struct ShortcutCardView: View {
    let shortcut: ShortcutItem
    let isDragging: Bool
    let trailingIcon: String
    var trailingColor: Color = .secondary
    let trailingAction: () -> Void
    let onTap: () -> Void
    var onEdit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Key chord chips
            HStack(spacing: 4) {
                if let mod = shortcut.modifier, !mod.isEmpty {
                    ForEach(mod.components(separatedBy: "+"), id: \.self) { m in
                        Text(m.trimmingCharacters(in: .whitespaces))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.82))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text("+")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                Text(shortcut.key)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.82))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer(minLength: 0)
            }

            // Description
            Text(shortcut.description)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // Bottom action row
            HStack {
                if let edit = onEdit {
                    Button(action: edit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: trailingAction) {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 15))
                        .foregroundColor(trailingColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 4, x: 0, y: 2)
        .opacity(isDragging ? 0.45 : 1.0)
        .scaleEffect(isDragging ? 0.96 : 1.0)
        .animation(.easeInOut(duration: 0.18), value: isDragging)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - ShortcutCardDropDelegate

struct ShortcutCardDropDelegate: DropDelegate {
    let item: ShortcutItem
    @Binding var items: [ShortcutItem]
    @Binding var draggingItem: ShortcutItem?

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingItem,
              dragging.id != item.id,
              let fromIdx = items.firstIndex(where: { $0.id == dragging.id }),
              let toIdx   = items.firstIndex(where: { $0.id == item.id })
        else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            items.move(
                fromOffsets: IndexSet(integer: fromIdx),
                toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - ProfileListRow

struct ProfileListRow: View {
    let profile: ShortcutProfileData
    let isActive: Bool
    let onTap: () -> Void
    let onShare: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 4)

                HStack(spacing: 12) {
                    Image(systemName: profile.icon)
                        .font(.title3)
                        .foregroundColor(hubColorFromHex(profile.themeColorHex))
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            if isActive { ActiveBadge() }
                        }
                        let catCount = profile.categories.count
                        let scCount  = profile.categories.reduce(0) { $0 + $1.shortcuts.count }
                        Text("\(catCount) \(catCount == 1 ? "category" : "categories") · \(scCount) shortcuts")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StripProfileListRow

struct StripProfileListRow: View {
    let strip: Rows23StripProfile
    let isActive: Bool
    let onTap: () -> Void
    let onSetActive: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 4)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(strip.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if isActive { ActiveBadge() }
                    }
                    let n = strip.slotMap.count
                    Text(n == 0
                         ? "Factory layout"
                         : "\(n) slot override\(n == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !isActive {
                    Button("Activate", action: onSetActive)
                        .buttonStyle(.bordered)
                        .font(.caption)
                        .tint(.accentColor)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
    }
}

// MARK: - ShortcutListRow

struct ShortcutListRow: View {
    let shortcut: ShortcutItem
    let trailingIcon: String
    var trailingColor: Color = .secondary
    let trailingAction: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                if let mod = shortcut.modifier, !mod.isEmpty {
                    ForEach(mod.components(separatedBy: "+"), id: \.self) { m in
                        KeyChip(text: m.trimmingCharacters(in: .whitespaces), isModifier: true)
                    }
                    Text("+")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                KeyChip(text: shortcut.key, isModifier: false)
            }
            .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.description)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: trailingAction) {
                Image(systemName: trailingIcon)
                    .font(.system(size: 18))
                    .foregroundColor(trailingColor)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - KeyChip

struct KeyChip: View {
    let text: String
    let isModifier: Bool

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isModifier ? Color.orange.opacity(0.82) : Color.accentColor.opacity(0.82))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - ActiveBadge

struct ActiveBadge: View {
    var body: some View {
        Text("Active")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.accentColor)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - StripSlotCatalogView

struct StripSlotCatalogView: View {
    let strip: Rows23StripProfile

    private struct PageDef: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let rows: [(rowNum: Int, cols: [String])]
    }

    private let pages: [PageDef] = [
        PageDef(id: "p0", title: "Page 0 — F-keys",
                subtitle: "Function keys F1–F12 and =",
                rows: [
                    (2, ["F7","F8","F9","F10","F11","F12","="]),
                    (3, ["F1","F2","F3","F4","F5","F6","FN"])
                ]),
        PageDef(id: "p1", title: "Page 1 — Modifiers & nav",
                subtitle: "Modifiers and navigation (default page)",
                rows: [
                    (2, ["Ctrl","Alt","Win","Tab","↑","Enter","…"]),
                    (3, ["Esc","Shift","Del","←","↓","→","FN"])
                ]),
        PageDef(id: "p2", title: "Page 2 — Punctuation",
                subtitle: "Symbols; local Fn toggles second layer",
                rows: [
                    (2, ["(",")",  "[",  "]",  ":",  "#",  "@"]),
                    (3, ["/","\\", "|",  "?",  "-",  "_",  "FN"])
                ]),
    ]

    var body: some View {
        List {
            ForEach(pages) { page in
                Section {
                    ForEach(page.rows, id: \.rowNum) { row in
                        HStack(spacing: 0) {
                            Text("R\(row.rowNum)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 22, alignment: .center)
                            HStack(spacing: 3) {
                                ForEach(row.cols.indices, id: \.self) { colIdx in
                                    let pageIdx = pages.firstIndex { $0.id == page.id } ?? 0
                                    let slotKey = "b-p\(pageIdx)r\(row.rowNum)c\(colIdx)"
                                    let overrideID = strip.slotMap[slotKey]
                                    let override  = overrideID.flatMap { oid in
                                        strip.shortcuts.first { $0.id == oid }
                                    }
                                    SlotCell(physicalLabel: row.cols[colIdx], override: override)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color(UIColor.systemBackground))
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.title).font(.caption.weight(.semibold))
                        Text(page.subtitle).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - SlotCell

struct SlotCell: View {
    let physicalLabel: String
    let override: ShortcutItem?

    var body: some View {
        if let ov = override {
            Text(String(ov.description.prefix(6)))
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(2)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(Color.accentColor)
                .cornerRadius(4)
        } else {
            Text(physicalLabel)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(2)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(4)
        }
    }
}

// MARK: - Color helper

func hubColorFromHex(_ hex: String) -> Color {
    let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "#", with: "")
    var rgb: UInt64 = 0
    Scanner(string: s).scanHexInt64(&rgb)
    return Color(
        red:   Double((rgb >> 16) & 0xFF) / 255.0,
        green: Double((rgb >>  8) & 0xFF) / 255.0,
        blue:  Double(rgb         & 0xFF) / 255.0
    )
}
