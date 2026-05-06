//
//  KeyAlternatesPopup.swift
//  KeyMod
//
//  3x3 grid popup for alternate character selection via gesture.
//  Synced from Android's showAlternatesPopup / AlternatePopupGeometry.
//

import SwiftUI

/// A single alternate option in a 3x3 grid slot.
struct AlternateOption: Identifiable {
    let id = UUID()
    let display: String
    let keyCode: String
    let requiresShift: Bool
    let slot: Int // AlternatePopupGeometry slot index
}

struct KeyAlternatesPopupView: View {
    let options: [AlternateOption] // non-nil slots
    let anchorFrame: CGRect
    let onCommit: (AlternateOption) -> Void
    let onCancel: () -> Void

    @State private var selectedSlot: Int = AlternatePopupGeometry.slotCenter
    @State private var gestureStart: CGPoint?

    // Geometry constants matching Android defaults (in points, approximate dp)
    private let rMinPx: CGFloat = 12
    private let rCancelPx: CGFloat = 228
    private let axisDeadzonePx: CGFloat = 18

    // Row-major layout: top row (UL, U, UR), mid row (L, C, R), bot row (DL, D, DR)
    private static let layout: [[Int]] = [
        [AlternatePopupGeometry.slotUpLeft, AlternatePopupGeometry.slotUp, AlternatePopupGeometry.slotUpRight],
        [AlternatePopupGeometry.slotLeft, AlternatePopupGeometry.slotCenter, AlternatePopupGeometry.slotRight],
        [AlternatePopupGeometry.slotDownLeft, AlternatePopupGeometry.slotDown, AlternatePopupGeometry.slotDownRight],
    ]

    var body: some View {
        GeometryReader { geometry in
            gridContent
                .position(x: anchorFrame.midX, y: anchorFrame.minY - 80)
                .gesture(dragGesture)
                .onAppear {
                    selectedSlot = AlternatePopupGeometry.slotCenter
                    gestureStart = nil
                }
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Grid building

    private var slotMap: [Int: AlternateOption] {
        var dict: [Int: AlternateOption] = [:]
        for opt in options { dict[opt.slot] = opt }
        return dict
    }

    private var gridContent: some View {
        let rows = Self.layout.map { row in
            row.map { slot in slotMap[slot] }
        }
        return gridBody(rows: rows)
    }

    private func gridBody(rows: [[AlternateOption?]]) -> some View {
        let rowViews = rows.map { row -> AnyView in
            let cells = row.map { cell -> AnyView in
                if let opt = cell {
                    return AnyView(optionCell(for: opt))
                } else {
                    return AnyView(Color.clear.frame(minWidth: 40, minHeight: 44))
                }
            }
            return AnyView(HStack(spacing: 2) { ForEach(Array(cells.indices), id: \.self) { AnyView(cells[$0]) } })
        }
        return VStack(spacing: 2) {
            ForEach(Array(rowViews.indices), id: \.self) { AnyView(rowViews[$0]) }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
        )
    }

    private func optionCell(for option: AlternateOption) -> some View {
        let isSelected = selectedSlot == option.slot
        return Text(option.display)
            .font(.system(size: 16, weight: .medium))
            .frame(minWidth: 40, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : Color(UIColor.secondarySystemBackground))
            )
            .foregroundColor(isSelected ? .white : .primary)
    }

    // MARK: - Gesture handling

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in updateSelection(from: value) }
            .onEnded { value in commitSelection(from: value) }
    }

    private func updateSelection(from value: DragGesture.Value) {
        if gestureStart == nil { gestureStart = value.location }
        guard let start = gestureStart else { return }

        let dx = value.location.x - start.x
        let dy = value.location.y - start.y
        let slot = AlternatePopupGeometry.pickSlot(
            dx: dx, dy: dy,
            rMinPx: rMinPx, rCancelPx: rCancelPx,
            axisDeadzonePx: axisDeadzonePx
        )

        if slot == -2 {
            onCancel()
        } else if slot == -1 {
            selectedSlot = AlternatePopupGeometry.slotCenter
        } else {
            selectedSlot = slot
        }
    }

    private func commitSelection(from value: DragGesture.Value) {
        guard let option = options.first(where: { $0.slot == selectedSlot }) else { return }
        onCommit(option)
    }
}
