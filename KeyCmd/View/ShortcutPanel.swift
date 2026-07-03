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
import UIKit

// MARK: - Data models

/// A single shortcut entry with icon and action
struct ShortcutEntry: Identifiable {
    let id = UUID()
    let label: String
    let icon: String?  // Asset catalog name, or SF Symbol name as fallback
    var badge: String? = nil  // optional badge shown bottom-right (e.g. "A"/"B")
    /// When true the button renders with a highlighted (tinted) background
    var isActive: Bool = false
    /// Optional custom font for the label (e.g. larger/bolder for F-keys)
    var font: Font? = nil
    /// Optional rotation for the icon in degrees (e.g. 180 for forward-delete)
    var iconRotation: Double = 0
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

// MARK: - Icon helper

/// Renders an icon from the asset catalog (template-tinted Material icons from Android),
/// falling back to an SF Symbol when no matching asset exists.
@ViewBuilder
func iconImage(_ name: String, size: CGFloat = 18) -> some View {
    if !name.isEmpty, UIImage(named: name) != nil {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    } else if !name.isEmpty {
        Image(systemName: name)
            .font(.system(size: size + 2))
    }
}

// MARK: - ShortcutButton (shared primitive)

struct ShortcutButton: View {
    let entry: ShortcutEntry
    var background: Color = Color(UIColor.tertiarySystemBackground)
    @ObservedObject private var prefs = KmProPrefs.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let mode = prefs.keysDisplayMode
        let wantsIcon = mode == .icons || mode == .combo
        let wantsLabel = mode == .names || mode == .combo
        // ponytail: Check asset catalog first, then SF Symbol availability.
        // If neither resolves, fall back to label text so the button isn't blank.
        let hasIcon: Bool = {
            guard let name = entry.icon, !name.isEmpty else { return false }
            if UIImage(named: name) != nil { return true }
            // SF Symbol fallback — check if the name produces a non-empty image
            return UIImage(systemName: name) != nil
        }()
        let showIcon = wantsIcon && hasIcon
        let showLabel = wantsLabel || (wantsIcon && !hasIcon)
        Button(action: entry.action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 1) {
                    if showIcon, let icon = entry.icon {
                        iconImage(icon, size: 22)
                            .rotationEffect(.degrees(entry.iconRotation))
                    }
                    if showLabel, !entry.label.isEmpty {
                        Text(entry.label)
                            .font(entry.font ?? .system(size: 8))
                            .lineLimit(1)
                    }
                }
                .foregroundColor(entry.isActive ? .white : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(entry.isActive ? themeManager.accentColor : background)
                .cornerRadius(8)

                if let badge = entry.badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.top, 3)
                        .offset(x: -3, y: 0)
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
                                background: ThemeManager.shared.accentColor.opacity(0.15)
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
    /// ponytail: external key to force row refresh when content changes (e.g. Fn toggle)
    var refreshKey: AnyHashable? = nil

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
                            VStack(spacing: 4) {
                                ShortcutStripRowView(entries: pages[idx].row1,
                                                    background: rowBackground)
                                    .id(refreshKey.map { "\($0)-\(idx)-r1" } ?? "\(idx)-r1")
                                ShortcutStripRowView(entries: pages[idx].row2,
                                                    background: rowBackground)
                                    .id(refreshKey.map { "\($0)-\(idx)-r2" } ?? "\(idx)-r2")
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
                .frame(height: 88)
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
        VStack(spacing: 4) {
            ShortcutStripRowView(entries: row1, background: rowBackground)
            ShortcutStripRowView(entries: row2, background: rowBackground)
        }
        .frame(height: 88)
    }
}

// MARK: - ShortcutStripRowView (single row of 7)

struct ShortcutStripRowView: View {
    let entries: [ShortcutEntry]
    var background: Color = Color(UIColor.tertiarySystemBackground)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { colIndex in
                if colIndex < entries.count {
                    ShortcutButton(entry: entries[colIndex], background: background)
                        .id(entries[colIndex].id)
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

// MARK: - Punctuation page data (shared between ProKeyboardMouseView and ComposeTextView)

enum PunctuationPageData {
    static let unlockedRow1: [(String, String)] = [
        ("(","`"),(")","~"),("[","'"),("]","\""),(":","%"),("#","^"),("@","|"),
    ]
    static let unlockedRow2: [(String, String)] = [
        ("/","<"),("\\",">"),("|","*"),("?","&"),("-","/"),("_","."),
    ]
    static let lockedRow1: [(String, String)] = [
        ("`","("),("~",")"),("'","["),("\"","]"),("%",":"),("^","#"),("|","@")
    ]
    static let lockedRow2: [(String, String)] = [
        ("<","/"),(">","\\"),("*","|"),("&","?"),(",","-"),(".","_")
    ]
}
