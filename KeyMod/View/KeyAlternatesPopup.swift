//
//  KeyAlternatesPopup.swift
//  KeyMod
//
//  Long-press → compact 3×3 grid popup above the anchor key.
//  Slide finger to pick a slot; lift to commit.
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

/// PickSlot result.
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

    private var slotMap: [Int: AlternateOption] {
        Dictionary(uniqueKeysWithValues: options.map { ($0.slot, $0) })
    }

    private static let gridLayout = [
        [AlternatePopupGeometry.slotUpLeft,   AlternatePopupGeometry.slotUp,   AlternatePopupGeometry.slotUpRight],
        [AlternatePopupGeometry.slotLeft,     AlternatePopupGeometry.slotCenter, AlternatePopupGeometry.slotRight],
        [AlternatePopupGeometry.slotDownLeft, AlternatePopupGeometry.slotDown, AlternatePopupGeometry.slotDownRight],
    ]

    // Only render rows/cols that have content (Android bounding-box shrink)
    private var visibleBounds: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) {
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
        return (minR, maxR, minC, maxC)
    }

    private let cellSize: CGFloat = 44
    private let cellMargin: CGFloat = 2
    private let cellFontSize: CGFloat = 18
    private let containerPadding: CGFloat = 6

    var body: some View {
        let bounds = visibleBounds
        let rowCount = bounds.maxRow - bounds.minRow + 1
        let colCount = bounds.maxCol - bounds.minCol + 1
        let cellSpacing = cellMargin

        // Total popup size
        let totalW = CGFloat(colCount) * cellSize + CGFloat(colCount - 1) * cellSpacing + containerPadding * 2
        let totalH = CGFloat(rowCount) * cellSize + CGFloat(rowCount - 1) * cellSpacing + containerPadding * 2

        VStack(spacing: cellSpacing) {
            ForEach(bounds.minRow...bounds.maxRow, id: \.self) { row in
                HStack(spacing: cellSpacing) {
                    ForEach(bounds.minCol...bounds.maxCol, id: \.self) { col in
                        cell(for: Self.gridLayout[row][col])
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
        .padding(containerPadding)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.2), radius: 6, y: 2)
        )
        .overlay(
            Group {
                if pick.isCancelled {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.25))
                }
            }
        )
        .frame(width: totalW, height: totalH)
        .position(x: anchorFrame.midX, y: anchorFrame.minY - totalH / 2 - 4)
    }

    @ViewBuilder
    private func cell(for slot: Int) -> some View {
        let opt = slotMap[slot]
        let selectedSlot = pick.selectedSlot
        let isSelected = slot == selectedSlot && !pick.isCancelled

        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue : Color(UIColor.secondarySystemBackground))
            if let opt = opt {
                Text(opt.display)
                    .font(.system(size: cellFontSize, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
            } else {
                Color.clear
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
