//
//  AlternatePopupGeometry.swift
//  KeyMod
//
//  Maps gesture offset (dx, dy) from anchor key to a 3x3 grid slot.
//  Synced from Android AlternatePopupGeometry.java.
//

import Foundation

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

    // Row-major: [row][col] -> slot index
    private static let gridToSlot = [
        [slotUpLeft, slotUp, slotUpRight],
        [slotLeft, slotCenter, slotRight],
        [slotDownLeft, slotDown, slotDownRight],
    ]

    /// Returns a slot index or RESULT_CANCEL / RESULT_DEFAULT.
    /// - dx/dy: gesture offset from gesture start
    /// - rMinPx: radius within which RESULT_DEFAULT is returned
    /// - rCancelPx: beyond this radius, cancel the popup
    /// - axisDeadzonePx: minimum |dx| or |dy| to register a direction
    static func pickSlot(dx: CGFloat, dy: CGFloat, rMinPx: CGFloat, rCancelPx: CGFloat, axisDeadzonePx: CGFloat) -> Int {
        let r = hypot(dx, dy)
        if r > rCancelPx { return -2 } // RESULT_CANCEL
        if r <= rMinPx { return -1 }   // RESULT_DEFAULT
        let col: Int = dx < -axisDeadzonePx ? 0 : (dx > axisDeadzonePx ? 2 : 1)
        let row: Int = dy < -axisDeadzonePx ? 0 : (dy > axisDeadzonePx ? 2 : 1)
        if row == 1 && col == 1 { return -1 } // RESULT_DEFAULT
        return gridToSlot[row][col]
    }
}
