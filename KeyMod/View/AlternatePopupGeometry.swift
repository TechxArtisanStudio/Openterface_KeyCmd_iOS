//
//  AlternatePopupGeometry.swift
//  KeyMod
//
//  Maps gesture offset (dx, dy) from anchor key to a 3x3 grid slot.
//  Synced from Android AlternatePopupGeometry.java.
//

import Foundation
import CoreGraphics

enum AlternatePopupGeometry {
    static let slotCount = 9

    static let slotCenter = 0
    static let slotUp = 1
    static let slotDown = 2
    static let slotLeft = 3
    static let slotRight = 4
    static let slotUpLeft = 5
    static let slotUpRight = 6
    static let slotDownLeft = 7
    static let slotDownRight = 8

    static let resultDefault = -1   // finger inside rMin or neutral cross → commit center
    static let resultCancel = -2    // oversized movement or empty cell → no commit

    // Row-major: [row][col] -> slot index
    private static let gridToSlot = [
        [slotUpLeft, slotUp, slotUpRight],
        [slotLeft, slotCenter, slotRight],
        [slotDownLeft, slotDown, slotDownRight],
    ]

    /// Returns a slot index or RESULT_CANCEL / RESULT_DEFAULT.
    /// - dx/dy: gesture offset from gesture start (screen coords, Y increases downward)
    /// - rMinPx: radius within which RESULT_DEFAULT is returned
    /// - rCancelPx: beyond this radius, cancel the popup
    /// - axisDeadzonePx: minimum |dx| or |dy| to register a direction
    /// - slotOccupied: true for slots that have an option; if false, returns RESULT_CANCEL
    static func pickSlot(dx: CGFloat, dy: CGFloat, rMinPx: CGFloat, rCancelPx: CGFloat, axisDeadzonePx: CGFloat, slotOccupied: [Bool]? = nil) -> Int {
        let r = hypot(dx, dy)
        if r > rCancelPx { return resultCancel }
        if r <= rMinPx { return resultDefault }
        let col: Int = dx < -axisDeadzonePx ? 0 : (dx > axisDeadzonePx ? 2 : 1)
        let row: Int = dy < -axisDeadzonePx ? 0 : (dy > axisDeadzonePx ? 2 : 1)
        if row == 1 && col == 1 { return resultDefault }
        let slot = gridToSlot[row][col]
        if let occ = slotOccupied, slot >= 0, slot < occ.count, !occ[slot] {
            return resultCancel
        }
        return slot
    }
}
