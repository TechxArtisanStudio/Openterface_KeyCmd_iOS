import Foundation
import SwiftUI

class MouseManager: ObservableObject {
    var bleManager: BLEManager
    @Published var previousPosition: CGPoint? = nil
    @Published var isSelectMode: Bool = false
    private let hapticManager = HapticFeedbackManager.shared

    init(bleManager: BLEManager) {
        self.bleManager = bleManager
    }

    // MARK: - Drag

    func handleDragChanged(currentPosition: CGPoint) {
        var xDelta = Int(currentPosition.x - (previousPosition?.x ?? currentPosition.x))
        var yDelta = Int(currentPosition.y - (previousPosition?.y ?? currentPosition.y))
        previousPosition = currentPosition
        let buttons: UInt8 = isSelectMode ? 0x01 : 0x00
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
            let packet = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: 0, wheel: 0)
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

    // MARK: - Drag mode toggle

    func handleDragModeToggle() {
        isSelectMode.toggle()
        print("Drag mode: \(isSelectMode ? "ON" : "OFF")")
        let buttons: UInt8 = isSelectMode ? 0x01 : 0x00
        let packet = Keymod.buildMouseRel(buttons: buttons, dx: 0, dy: 0, wheel: 0)
        bleManager.sendTouchData(data: packet)
    }

    // MARK: - Scroll

    func handleScroll(deltaX: Int, deltaY: Int) {
        print("Performing scroll action - deltaX: \(deltaX), deltaY: \(deltaY)")
        let scrollSensitivity = 3
        let boundedDeltaY = Int8(max(-127, min(127, deltaY * scrollSensitivity)))
        let boundedDeltaX = Int8(max(-127, min(127, deltaX * scrollSensitivity)))

        // Vertical scroll
        let vPacket = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: 0, wheel: boundedDeltaY)
        bleManager.sendTouchData(data: vPacket)

        // Horizontal scroll (separate packet if supported)
        if boundedDeltaX != 0 {
            let hPacket = Keymod.buildMouseRel(buttons: 0x00, dx: 0, dy: Int8(boundedDeltaX), wheel: 0)
            bleManager.sendTouchData(data: hPacket)
        }
    }
}
