//
//  KeyAlternatesPopup.swift
//  KeyMod
//
//  Long-press → 3×3 grid popup above the anchor key.
//  Slide finger to pick a slot; lift to commit.
//  Ported from Android CustomKeyboardView.showAlternatesPopup().
//

import SwiftUI

/// A single alternate option mapped to a 3×3 grid slot.
struct AlternateOption: Identifiable {
    let id = UUID()
    let display: String
    let keyCode: String
    let requiresShift: Bool
    let slot: Int // AlternatePopupGeometry slot index
}

/// PickSlot result that the popup renders.
enum AlternatesPick: Equatable {
    case none             // initial
    case defaultSlot      // finger inside rMin or neutral cross → center
    case slot(Int)        // specific grid slot
    case cancel           // finger outside rCancel → no commit

    var selectedSlot: Int? {
        if case .slot(let s) = self { return s }
        if case .defaultSlot = self { return AlternatePopupGeometry.slotCenter }
        return nil
    }

    var isCancelled: Bool {
        if case .cancel = self { return true }
        return false
    }
}

struct KeyAlternatesPopupView: View {
    let options: [AlternateOption]
    let anchorFrame: CGRect
    var pick: AlternatesPick

    // Slot → option lookup
    private var slotMap: [Int: AlternateOption] {
        Dictionary(uniqueKeysWithValues: options.map { ($0.slot, $0) })
    }

    // 3×3 grid layout: [row][col] = slot
    private static let gridLayout = [
        [AlternatePopupGeometry.slotUpLeft,   AlternatePopupGeometry.slotUp,   AlternatePopupGeometry.slotUpRight],
        [AlternatePopupGeometry.slotLeft,     AlternatePopupGeometry.slotCenter, AlternatePopupGeometry.slotRight],
        [AlternatePopupGeometry.slotDownLeft, AlternatePopupGeometry.slotDown, AlternatePopupGeometry.slotDownRight],
    ]

    // Only render rows/cols that have content (Android bounding-box shrink)
    private var visibleBounds: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int, hasAny: Bool) {
        var minR = 2, maxR = 0, minC = 2, maxC = 0
        for r in 0..<3 {
            for c in 0..<3 {
                if slotMap[Self.gridLayout[r][c]] != nil {
                    if r < minR { minR = r }
                    if r > maxR { maxR = r }
                    if c < minC { minC = c }
                    if c > maxC { maxC = c }
                }
            }
        }
        return (minR, maxR, minC, maxC, maxR >= minR)
    }

    private let cellMinSize: CGFloat = 32
    private let cellPaddingH: CGFloat = 6
    private let cellPaddingV: CGFloat = 4
    private let cellMargin: CGFloat = 2
    private let cellFontSize: CGFloat = 15

    var body: some View {
        GeometryReader { geo in
            let bounds = visibleBounds
            let selectedSlot = pick.selectedSlot
            let isCancelled = pick.isCancelled

            VStack(spacing: cellMargin) {
                ForEach(bounds.minRow...bounds.maxRow, id: \.self) { row in
                    HStack(spacing: cellMargin) {
                        ForEach(bounds.minCol...bounds.maxCol, id: \.self) { col in
                            let slot = Self.gridLayout[row][col]
                            let opt = slotMap[slot]
                            let isSelected = slot == selectedSlot && !isCancelled

                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.blue : Color(UIColor.secondarySystemBackground))
                                if let opt = opt {
                                    Text(opt.display)
                                        .font(.system(size: cellFontSize, weight: isSelected ? .semibold : .regular))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .minimumScaleFactor(0.5)
                                        .lineLimit(1)
                                } else {
                                    // Empty cell — dim spacer
                                    Color.clear
                                        .frame(minWidth: cellMinSize, minHeight: cellMinSize)
                                        .opacity(0.3)
                                }
                            }
                            .frame(minWidth: cellMinSize, minHeight: cellMinSize)
                            .padding(.horizontal, cellPaddingH)
                            .padding(.vertical, cellPaddingV)
                        }
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
            )
            .overlay(
                // Visual dim for cancel state
                Group {
                    if isCancelled {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.3))
                    }
                }
            )
            .position(x: popupPosition(in: geo), y: popupY(in: geo))
        }
        .animation(.easeOut(duration: 0.1), value: pick)
    }

    private func popupPosition(in geo: GeometryProxy) -> CGFloat {
        let midX = anchorFrame.midX
        return min(max(midX, 60), geo.size.width - 60)
    }

    private func popupY(in geo: GeometryProxy) -> CGFloat {
        // Position above anchor key, with extra offset if bottom row has alternates
        let hasBottomRow = slotMap[AlternatePopupGeometry.slotDownLeft] != nil
            || slotMap[AlternatePopupGeometry.slotDown] != nil
            || slotMap[AlternatePopupGeometry.slotDownRight] != nil
        let extra = hasBottomRow ? 20.0 : 0.0
        let popupHeight: CGFloat = CGFloat(visibleBounds.maxRow - visibleBounds.minRow + 1) * (cellMinSize + cellPaddingV * 2 + cellMargin) + 16
        return anchorFrame.minY - popupHeight / 2 - 16 - extra
    }
}
