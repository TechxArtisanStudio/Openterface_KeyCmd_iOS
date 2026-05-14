//
//  KeyAlternatesPopup.swift
//  KeyMod
//
//  System-keyboard-style horizontal alternates popup.
//  Long-press a key → horizontal bubble strip appears above the key.
//  Slide left/right to highlight a character; lift finger to commit.
//

import SwiftUI

/// A single alternate option.
struct AlternateOption: Identifiable {
    let id = UUID()
    let display: String
    let keyCode: String
    let requiresShift: Bool
    let slot: Int // AlternatePopupGeometry slot index (kept for API compat)
}

struct KeyAlternatesPopupView: View {
    let options: [AlternateOption]
    let anchorFrame: CGRect
    /// Current drag location in the parent coordinate space (proKMView).
    var dragLocation: CGPoint?
    /// Binding to parent-owned selected index so parent can commit on drag end.
    @Binding var selectedIndex: Int
    let onCommit: (AlternateOption) -> Void
    let onCancel: () -> Void

    // Sorted display order: center slot first, then left, right, up, down, corners
    private var sortedOptions: [AlternateOption] {
        let order = [
            AlternatePopupGeometry.slotCenter,
            AlternatePopupGeometry.slotLeft,
            AlternatePopupGeometry.slotRight,
            AlternatePopupGeometry.slotUp,
            AlternatePopupGeometry.slotDown,
            AlternatePopupGeometry.slotUpLeft,
            AlternatePopupGeometry.slotUpRight,
            AlternatePopupGeometry.slotDownLeft,
            AlternatePopupGeometry.slotDownRight,
        ]
        let slotMap = Dictionary(uniqueKeysWithValues: options.map { ($0.slot, $0) })
        return order.compactMap { slotMap[$0] }
    }

    @State private var stripOriginX: CGFloat = 0

    private let cellWidth: CGFloat = 36
    private let cellHeight: CGFloat = 44
    private let cellSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let sorted = sortedOptions
            let popupWidth = CGFloat(sorted.count) * (cellWidth + cellSpacing) - cellSpacing + 16
            let idealX = anchorFrame.midX - popupWidth / 2
            let clampedX = min(max(idealX, 4), geometry.size.width - popupWidth - 4)
            let popupY = anchorFrame.minY - cellHeight - 16

            popupStrip(sorted: sorted)
                .frame(width: popupWidth)
                .position(x: clampedX + popupWidth / 2, y: popupY + cellHeight / 2)
                .onAppear {
                    selectedIndex = 0
                    stripOriginX = clampedX + 8
                }
                .onChange(of: dragLocation) { loc in
                    guard let loc = loc else { return }
                    updateSelectionFromDrag(loc: loc, sorted: sorted, stripOriginX: clampedX + 8)
                }
        }
    }

    /// Map the drag X position (in proKMView coords) to a cell index.
    private func updateSelectionFromDrag(loc: CGPoint, sorted: [AlternateOption], stripOriginX: CGFloat) {
        let step = cellWidth + cellSpacing
        let localX = loc.x - stripOriginX
        let idx = Int(localX / step)
        let clamped = max(0, min(sorted.count - 1, idx))
        if clamped != selectedIndex { selectedIndex = clamped }
    }

    private func popupStrip(sorted: [AlternateOption]) -> some View {
        HStack(spacing: cellSpacing) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { idx, opt in
                let isSelected = idx == selectedIndex
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color(UIColor.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 0.5)
                        )
                    Text(opt.display)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .primary)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: cellWidth, height: cellHeight)
                .scaleEffect(isSelected ? 1.15 : 1.0)
                .animation(.spring(response: 0.15, dampingFraction: 0.7), value: isSelected)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
        )
    }
}
