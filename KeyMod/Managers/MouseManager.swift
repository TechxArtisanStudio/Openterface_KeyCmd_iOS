import Foundation
import SwiftUI

class MouseManager: ObservableObject {
    var bleManager: BLEManager
    @Published var previousPosition: CGPoint? = nil
    @Published var isSelectMode: Bool = false
    /// Bitmask of buttons currently held via the L/M/R press buttons (0x01=L, 0x02=R, 0x04=M).
    @Published var heldButtons: UInt8 = 0
    @ObservedObject private var touchpadSettings = TouchpadSettings.shared
    private let hapticManager = HapticFeedbackManager.shared

    init(bleManager: BLEManager) {
        self.bleManager = bleManager
    }

    // MARK: - Drag

    func handleDragChanged(currentPosition: CGPoint) {
        var xDelta = Int(currentPosition.x - (previousPosition?.x ?? currentPosition.x))
        var yDelta = Int(currentPosition.y - (previousPosition?.y ?? currentPosition.y))
        previousPosition = currentPosition
        let buttons: UInt8 = heldButtons | (isSelectMode ? 0x01 : 0x00)
        xDelta *= 4
        yDelta *= 4
        let boundedXDelta = Int8(max(-127, min(127, xDelta)))
        let boundedYDelta = Int8(max(-127, min(127, yDelta)))
        let packet = Keymod.buildMouseRel(buttons: buttons, dx: boundedXDelta, dy: boundedYDelta, wheel: 0)
        bleManager.sendTouchData(data: packet)
    }

    func handleDragEnded() {
        previousPosition = nil
        if !isSelectMode {
            let packet = Keymod.buildMouseRel(buttons: heldButtons, dx: 0, dy: 0, wheel: 0)
            bleManager.sendTouchData(data: packet)
        }
    }

    // MARK: - Clicks

    func handleDoubleClick() {
        print("Performing double click action")
        hapticManager.triggerMediumFeedback()

        let press = Keymod.buildMouseRel(buttons: 0x01, dx: 0, dy: 0, wheel: 0)
        bleManager.sendTouchData(data: press)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let release1 = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: 0, wheel: 0)
            self.bleManager.sendTouchData(data: release1)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let press2 = Keymod.buildMouseRel(buttons: 0x01, dx: 0, dy: 0, wheel: 0)
                self.bleManager.sendTouchData(data: press2)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let release2 = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: 0, wheel: 0)
                    self.bleManager.sendTouchData(data: release2)
                }
            }
        }
    }

    func handleClick() {
        print("Performing click action")
        hapticManager.triggerButtonPress()

        let press = Keymod.buildMouseRel(buttons: 0x01, dx: 0, dy: 0, wheel: 0)
        bleManager.sendTouchData(data: press)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let release = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: 0, wheel: 0)
            self.bleManager.sendTouchData(data: release)
        }
    }

    func handleRightClick() {
        print("Performing right click action")
        hapticManager.triggerButtonPress()

        let press = Keymod.buildMouseRel(buttons: 0x02, dx: 0, dy: 0, wheel: 0)
        bleManager.sendTouchData(data: press)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let release = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: 0, wheel: 0)
            self.bleManager.sendTouchData(data: release)
        }
    }

    /// Middle click (button=0x04). Matches Android MouseRelHidTransport.sendMiddleClick().
    func handleMiddleClick() {
        print("Performing middle click action")
        hapticManager.triggerButtonPress()

        let press = Keymod.buildMouseRel(buttons: 0x04, dx: 0, dy: 0, wheel: 0)
        bleManager.sendTouchData(data: press)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let release = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: 0, wheel: 0)
            self.bleManager.sendTouchData(data: release)
        }
    }

    // MARK: - Press / Release (for L/M/R hold buttons)

    func sendButtonDown(buttons: UInt8) {
        heldButtons |= buttons
        let packet = Keymod.buildMouseRel(buttons: heldButtons, dx: 0, dy: 0, wheel: 0)
        bleManager.sendTouchData(data: packet)
    }

    func sendButtonUp(buttons: UInt8) {
        heldButtons &= ~buttons
        let packet = Keymod.buildMouseRel(buttons: heldButtons, dx: 0, dy: 0, wheel: 0)
        bleManager.sendTouchData(data: packet)
    }

    // MARK: - Drag mode toggle

    func handleDragModeToggle() {
        isSelectMode.toggle()
        print("Drag mode: \(isSelectMode ? "ON" : "OFF")")
        let buttons: UInt8 = isSelectMode ? 0x01 : 0x00
        let packet = Keymod.buildMouseRel(buttons: buttons, dx: 0, dy: 0, wheel: 0)
        bleManager.sendTouchData(data: packet)
    }

    // MARK: - Scroll

    /// Send scroll with pre-computed integer deltas.
    /// TouchpadView handles fractional accumulation and sensitivity.
    /// Vertical scroll uses wheel byte; horizontal scroll uses dx byte (separate packets).
    /// Matches Android sendScroll: vertical packet has wheel in byte 4, horizontal has dx in byte 2.
    func handleScroll(deltaX: Int, deltaY: Int) {
        guard deltaX != 0 || deltaY != 0 else { return }

        // Vertical scroll (wheel byte)
        if deltaY != 0 {
            let boundedY = Int8(max(-127, min(127, deltaY)))
            let vPacket = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: 0, wheel: boundedY)
            bleManager.sendTouchData(data: vPacket)
        }

        // Horizontal scroll (dx byte)
        if deltaX != 0 {
            let boundedX = Int8(max(-127, min(127, deltaX)))
            let hPacket = Keymod.buildMouseRel(buttons: 0x00, dx: boundedX, dy: 0, wheel: 0)
            bleManager.sendTouchData(data: hPacket)
        }
    }
}
