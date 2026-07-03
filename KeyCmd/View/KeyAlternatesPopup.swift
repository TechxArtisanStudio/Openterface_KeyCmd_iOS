//
//  KeyAlternatesPopup.swift
//  KeyMod
//
//  Long-press → horizontal 3-cell popup above the anchor key.
//  Slide finger to pick a slot; lift to commit.
//

import SwiftUI

/// A single alternate option mapped to a horizontal slot (left/center/right).
struct AlternateOption: Identifiable {
    let id = UUID()
    let display: String
    let keyCode: String
    let requiresShift: Bool
    /// Bitmask of extra modifiers: 0x04 = Alt, 0x08 = Win, 0x10 = Ctrl, 0x20 = ShiftR, etc.
    /// 0x01 = Ctrl, 0x02 = Shift, 0x04 = Alt, 0x08 = Win
    let modifierMask: UInt8
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
    var isVertical: Bool = false
    var isTwoCell: Bool = false

    @ObservedObject private var themeManager = ThemeManager.shared

    private var slotMap: [Int: AlternateOption] {
        Dictionary(uniqueKeysWithValues: options.map { ($0.slot, $0) })
    }

    // Horizontal 3-cell layout: [Left, Center, Right]
    private static let horizontalLayout = [
        [AlternatePopupGeometry.slotLeft, AlternatePopupGeometry.slotCenter, AlternatePopupGeometry.slotRight],
    ]

    // Horizontal 2-cell layout: [Left, Center]
    private static let twoCellLayout = [
        [AlternatePopupGeometry.slotLeft, AlternatePopupGeometry.slotCenter],
    ]

    // Vertical layout: 3 rows with Up/Center/Down
    private static let verticalLayout = [
        [AlternatePopupGeometry.slotUp],
        [AlternatePopupGeometry.slotCenter],
        [AlternatePopupGeometry.slotDown],
    ]

    private var gridLayout: [[Int]] {
        if isVertical {
            return Self.verticalLayout
        } else if isTwoCell {
            return Self.twoCellLayout
        } else {
            return Self.horizontalLayout
        }
    }

    private var visibleBounds: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int) {
        if isVertical {
            return (0, 2, 0, 0)  // 3 rows, 1 column
        } else if isTwoCell {
            return (0, 0, 0, 1)  // 1 row, 2 columns
        } else {
            return (0, 0, 0, 2)  // 1 row, 3 columns
        }
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
                        cell(for: gridLayout[row][col])
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .fill(isSelected ? themeManager.accentColor : Color(UIColor.secondarySystemBackground))
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
