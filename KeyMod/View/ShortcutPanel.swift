//
//  ShortcutPanel.swift
//  KeyMod
//
//  Swipeable shortcut panels matching Android's topShortcutPanels.
//  7-column x 2-row grid with pagination and swipe gestures.
//

import SwiftUI

/// A single shortcut entry with icon and action
struct ShortcutEntry: Identifiable {
    let id = UUID()
    let label: String
    let icon: String?  // SF Symbol name, nil for text-only
    let action: () -> Void
}

/// A page of shortcuts (up to 14 = 7 columns x 2 rows)
struct ShortcutPage {
    let title: String
    let entries: [ShortcutEntry]
}

/// A swipeable panel containing shortcut pages
struct ShortcutPanel: View {
    let pages: [ShortcutPage]
    @State private var currentPageIndex: Int = 0

    var body: some View {
        if pages.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Page title
                    Text(pages[currentPageIndex].title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 2)

                    // 2 rows of 7 buttons
                    ForEach(0..<2, id: \.self) { rowIndex in
                        HStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { colIndex in
                                let entryIndex = rowIndex * 7 + colIndex
                                if entryIndex < pages[currentPageIndex].entries.count {
                                    let entry = pages[currentPageIndex].entries[entryIndex]
                                    ShortcutButton(entry: entry)
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                }
                .padding(2)
            }
        )
    }
}

/// Swipeable shortcut panel pager
struct ShortcutPanelPager: View {
    let pages: [ShortcutPage]
    @State private var currentPageIndex: Int = 0

    var body: some View {
        if pages.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            VStack(spacing: 0) {
                TabView(selection: $currentPageIndex) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        ShortcutPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 90)

                // Page indicator dots
                if pages.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPageIndex ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        )
    }
}

struct ShortcutPageView: View {
    let page: ShortcutPage

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                // Page title removed to save space
                // Text(page.title)
                //     .font(.system(size: 9, weight: .bold))
                //     .foregroundColor(.secondary)
                //     .frame(maxWidth: .infinity, alignment: .center)
                //     .padding(.vertical, 1)

                // 2 rows of 7 buttons
                ForEach(0..<2, id: \.self) { rowIndex in
                    HStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { colIndex in
                            let entryIndex = rowIndex * 7 + colIndex
                            if entryIndex < page.entries.count {
                                ShortcutButton(entry: page.entries[entryIndex])
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
            .padding(2)
        }
    }
}

struct ShortcutButton: View {
    let entry: ShortcutEntry

    var body: some View {
        Button(action: entry.action) {
            VStack(spacing: 1) {
                if let icon = entry.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(entry.label)
                    .font(.system(size: 8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(4)
        }
    }
}
