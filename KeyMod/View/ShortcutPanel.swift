//
//  ShortcutPanel.swift
//  KeyMod
//
//  Android-parity shortcut strip layout:
//    Row 1  — pageable favorites strip  (ShortcutStripPager, ~44px + 9px dots)
//    Rows 2–3 — pageable fixed strip    (FixedRowsPager, ~88px + 9px dots)
//               Page 0: F-keys (F7–F12/= | F1–F6/FN)
//               Page 1: Modifiers + Navigation (default)
//               Page 2: Punctuation symbols
//  Total ≈ 150px, matching Android's three-row shortcut strip.
//

import SwiftUI

// MARK: - Data models

/// A single shortcut entry with icon and action
struct ShortcutEntry: Identifiable {
    let id = UUID()
    let label: String
    let icon: String?  // SF Symbol name, nil for text-only
    var badge: String? = nil  // optional badge shown bottom-right (e.g. "A"/"B")
    /// When true the button renders with a highlighted (tinted) background
    var isActive: Bool = false
    let action: () -> Void
}

/// A page of shortcuts (7 entries = 1 row of 7 columns)
struct ShortcutPage {
    let title: String
    let entries: [ShortcutEntry]
}

/// A two-row page for the fixed rows 2–3 strip
struct FixedRowsPage {
    let row1: [ShortcutEntry]  // row 2 (top)
    let row2: [ShortcutEntry]  // row 3 (bottom)
}

// MARK: - ShortcutButton (shared primitive)

struct ShortcutButton: View {
    let entry: ShortcutEntry
    var background: Color = Color(UIColor.tertiarySystemBackground)

    var body: some View {
        Button(action: entry.action) {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 1) {
                    if let icon = entry.icon {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                    }
                    if !entry.label.isEmpty {
                        Text(entry.label)
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                }
                .foregroundColor(entry.isActive ? .white : .white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(entry.isActive ? Color.blue : background)
                .cornerRadius(4)

                if let badge = entry.badge {
                    Text(badge)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                        .background(Color.orange)
                        .cornerRadius(2)
                        .offset(x: 2, y: 2)
                }
            }
        }
    }
}

// MARK: - ShortcutStripPager (row 1 — horizontally scrollable favorites)

/// Swipeable single-row pager — 7 shortcuts per page.
/// Matches Android behavior where the whole row flips page together.
/// Apply `.id(profileId)` at the call site to reset to page 0 on profile switch.
struct ShortcutStripPager: View {
    let pages: [ShortcutPage]

    @State private var currentPage: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    var body: some View {
        if !pages.isEmpty {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let w = geo.size.width
                    HStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { idx in
                            ShortcutStripRowView(
                                entries: pages[idx].entries,
                                background: Color.orange.opacity(0.18)
                            )
                            .frame(width: w)
                        }
                    }
                    .offset(x: -CGFloat(currentPage) * w + dragOffset)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8),
                               value: currentPage)
                    .frame(width: w, alignment: .leading)
                    .clipped()
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onChanged { v in
                                dragOffset = v.translation.width
                            }
                            .onEnded { v in
                                let threshold = w * 0.12
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if v.translation.width < -threshold,
                                       currentPage < pages.count - 1 {
                                        currentPage += 1
                                    } else if v.translation.width > threshold,
                                              currentPage > 0 {
                                        currentPage -= 1
                                    }
                                    dragOffset = 0
                                }
                            }
                    )
                }
                .frame(height: 40)
            }
        }
    }
}

// MARK: - FixedRowsPager (rows 2–3 — pageable, 4 pages)

/// Swipeable 2-row pager mirroring Android's fixedTopRowsViewport (4 pages).
/// Uses DragGesture + offset so it works correctly inside a vertical ScrollView.
/// Default page index 1 = modifiers + navigation (FIXED_TOP_ROWS_DEFAULT_PAGE_INDEX = 1).
struct FixedRowsPager: View {
    let pages: [FixedRowsPage]
    var defaultPageIndex: Int = 1

    @State private var currentPage: Int = -1
    @State private var dragOffset: CGFloat = 0

    private let rowBackground = Color(UIColor.tertiarySystemBackground)

    private var activePage: Int {
        currentPage < 0 ? min(defaultPageIndex, max(0, pages.count - 1)) : currentPage
    }

    var body: some View {
        if !pages.isEmpty {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let w = geo.size.width
                    HStack(spacing: 0) {
                        ForEach(0..<pages.count, id: \.self) { idx in
                            VStack(spacing: 2) {
                                ShortcutStripRowView(entries: pages[idx].row1,
                                                    background: rowBackground)
                                ShortcutStripRowView(entries: pages[idx].row2,
                                                    background: rowBackground)
                            }
                            .padding(.horizontal, 0)
                            .frame(width: w)
                        }
                    }
                    .offset(x: -CGFloat(activePage) * w + dragOffset)
                    .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8),
                               value: activePage)
                    .frame(width: w, alignment: .leading)
                    .clipped()
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onChanged { v in
                                dragOffset = v.translation.width
                            }
                            .onEnded { v in
                                let threshold = w * 0.12
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if v.translation.width < -threshold,
                                       activePage < pages.count - 1 {
                                        currentPage = activePage + 1
                                    } else if v.translation.width > threshold,
                                              activePage > 0 {
                                        currentPage = activePage - 1
                                    }
                                    dragOffset = 0
                                }
                            }
                    )
                }
                .frame(height: 86)
                .onAppear {
                    if currentPage < 0 {
                        currentPage = min(defaultPageIndex, pages.count - 1)
                    }
                }
            }
        }
    }
}

// MARK: - ShortcutFixedRowsView (rows 2–3 — static, kept for backward compat)

/// Two always-visible rows of 7 buttons each (non-pageable).
struct ShortcutFixedRowsView: View {
    let row1: [ShortcutEntry]
    let row2: [ShortcutEntry]

    private let rowBackground = Color(UIColor.tertiarySystemBackground)

    var body: some View {
        VStack(spacing: 2) {
            ShortcutStripRowView(entries: row1, background: rowBackground)
            ShortcutStripRowView(entries: row2, background: rowBackground)
        }
        .frame(height: 86)
    }
}

// MARK: - ShortcutStripRowView (single row of 7)

struct ShortcutStripRowView: View {
    let entries: [ShortcutEntry]
    var background: Color = Color(UIColor.tertiarySystemBackground)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { colIndex in
                if colIndex < entries.count {
                    ShortcutButton(entry: entries[colIndex], background: background)
                } else {
                    ShortcutButton(entry: ShortcutEntry(label: "", icon: nil) {}, background: background)
                        .disabled(true)
                        .opacity(0.3)
                }
            }
        }
        .padding(.horizontal, 2)
    }
}
