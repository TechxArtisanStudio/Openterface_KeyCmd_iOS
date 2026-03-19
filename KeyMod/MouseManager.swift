import Foundation

class MouseManager: ObservableObject {
    var bleManager: BLEManager // Make this internal and settable
    @Published var previousPosition: CGPoint? = nil
    @Published var isSelectMode: Bool = false // Track drag mode state
    private let hapticManager = HapticFeedbackManager.shared

    init(bleManager: BLEManager) {
        self.bleManager = bleManager
    }

    // Add handlers for drag events
    func handleDragChanged(currentPosition: CGPoint) {
        var xDelta = Int(currentPosition.x - (previousPosition?.x ?? currentPosition.x))
        var yDelta = Int(currentPosition.y - (previousPosition?.y ?? currentPosition.y))
        previousPosition = currentPosition
        let mousePressed = isSelectMode ? 0x01 : 0x00 // Use drag mode state
        let wheelMove = 0x00
        xDelta *= 4
        yDelta *= 4
        let boundedXDelta = max(-127, min(127, xDelta))
        let boundedYDelta = max(-127, min(127, yDelta))
        let xDirection = boundedXDelta >= 0 ? boundedXDelta : (0x100 + boundedXDelta)
        let yDirection = boundedYDelta >= 0 ? boundedYDelta : (0x100 + boundedYDelta)
        var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), UInt8(xDirection), UInt8(yDirection), UInt8(wheelMove)]
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        bleManager.sendTouchData(data: Data(dataPacket))
    }

    func handleDragEnded() {
        previousPosition = nil
        if !isSelectMode {
            let mouseReleased = 0x00
            let dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00, 0x63]
            bleManager.sendTouchData(data: Data(dataPacket))
        }
    }

    func handleDoubleClick() {
        print("Performing double click action")
        
        // Trigger medium haptic feedback for double click
        hapticManager.triggerMediumFeedback()
        
        // Send first click
        let mousePressed = 0x01
        var clickDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), 0x00, 0x00, 0x00]
        let sum = clickDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        clickDataPacket.append(UInt8(sum))
        bleManager.sendTouchData(data: Data(clickDataPacket))
        
        // Release first click
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let mouseReleased = 0x00
            var releaseDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00]
            let releaseSum = releaseDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            releaseDataPacket.append(UInt8(releaseSum))
            self.bleManager.sendTouchData(data: Data(releaseDataPacket))
            
            // Send second click after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                var secondClickDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), 0x00, 0x00, 0x00]
                let secondSum = secondClickDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
                secondClickDataPacket.append(UInt8(secondSum))
                self.bleManager.sendTouchData(data: Data(secondClickDataPacket))
                
                // Release second click
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    var secondReleaseDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00]
                    let secondReleaseSum = secondReleaseDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
                    secondReleaseDataPacket.append(UInt8(secondReleaseSum))
                    self.bleManager.sendTouchData(data: Data(secondReleaseDataPacket))
                }
            }
        }
    }
    
    func handleDragModeToggle() {
        isSelectMode.toggle()
        print("Drag mode: \(isSelectMode ? "ON" : "OFF")")
        
        // Send appropriate mouse state
        let mouseState = isSelectMode ? 0x01 : 0x00
        var dataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseState), 0x00, 0x00, 0x00]
        let sum = dataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        dataPacket.append(UInt8(sum))
        bleManager.sendTouchData(data: Data(dataPacket))
    }

    func handleRightClick() {
        print("Performing right click action")
        
        // Trigger haptic feedback for right click
        hapticManager.triggerButtonPress()
        
        // Send a right click event (press and release)
        // Right click is usually button 2 (0x02)
        let rightMousePressed = 0x02
        var rightClickDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(rightMousePressed), 0x00, 0x00, 0x00]
        let sum = rightClickDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        rightClickDataPacket.append(UInt8(sum))
        bleManager.sendTouchData(data: Data(rightClickDataPacket))
        
        // Small delay and then release
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let mouseReleased = 0x00
            var releaseDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00]
            let releaseSum = releaseDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            releaseDataPacket.append(UInt8(releaseSum))
            self.bleManager.sendTouchData(data: Data(releaseDataPacket))
        }
    }

    func handleClick() {
        print("Performing click action")
        
        // Trigger haptic feedback for click
        hapticManager.triggerButtonPress()
        
        // Send a click event (press and release)
        let mousePressed = 0x01
        var clickDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mousePressed), 0x00, 0x00, 0x00]
        let sum = clickDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        clickDataPacket.append(UInt8(sum))
        bleManager.sendTouchData(data: Data(clickDataPacket))
        
        // Small delay and then release
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let mouseReleased = 0x00
            var releaseDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, UInt8(mouseReleased), 0x00, 0x00, 0x00]
            let releaseSum = releaseDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            releaseDataPacket.append(UInt8(releaseSum))
            self.bleManager.sendTouchData(data: Data(releaseDataPacket))
        }
    }

    func handleScroll(deltaX: Int, deltaY: Int) {
        print("Performing scroll action - deltaX: \(deltaX), deltaY: \(deltaY)")
        
        // Convert scroll deltas to appropriate wheel values
        // Positive deltaY means scroll up, negative means scroll down
        // Adjust sensitivity - make scrolling more responsive
        let scrollSensitivity = 3
        let boundedDeltaY = max(-127, min(127, deltaY * scrollSensitivity))
        let boundedDeltaX = max(-127, min(127, deltaX * scrollSensitivity))
        
        // For vertical scrolling, use wheelMove (deltaY)
        let wheelMove = boundedDeltaY >= 0 ? boundedDeltaY : (0x100 + boundedDeltaY)
        
        // Create scroll packet - no mouse button pressed, no movement, just wheel
        var scrollDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, 0x00, 0x00, 0x00, UInt8(wheelMove)]
        let sum = scrollDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
        scrollDataPacket.append(UInt8(sum))
        bleManager.sendTouchData(data: Data(scrollDataPacket))
        
        // If there's horizontal scrolling, send a separate packet (if supported)
        if boundedDeltaX != 0 {
            // Some systems support horizontal scrolling via different mechanisms
            // This might need adjustment based on the receiving system
            let horizontalWheel = boundedDeltaX >= 0 ? boundedDeltaX : (0x100 + boundedDeltaX)
            var hScrollDataPacket: [UInt8] = [0x57, 0xAB, 0x00, 0x05, 0x05, 0x01, 0x00, UInt8(horizontalWheel), 0x00, 0x00]
            let hSum = hScrollDataPacket.reduce(0 as UInt32, { $0 + UInt32($1) }) & 0xFF
            hScrollDataPacket.append(UInt8(hSum))
            bleManager.sendTouchData(data: Data(hScrollDataPacket))
        }
    }
}
