import UIKit

/// Tracks active touches and maps each to a key. Fires callbacks on press/release/move.
///
/// The generic parameter `Touch` allows unit testing with a mock type instead of `UITouch`.
/// In production, `Touch` is `UITouch`. The only requirement is `Hashable` identity.
final class TouchTracker<Touch: Hashable> {

    /// Called when a touch begins on a key. (keyName, keyType)
    var onPress: ((String, KeyType) -> Void)?
    /// Called when a touch ends or is cancelled. (keyName, keyType)
    var onRelease: ((String, KeyType) -> Void)?
    /// Called when a touch moves. (point, keyName)
    var onMoved: ((CGPoint, String) -> Void)?

    /// Maps each active touch to its current key registration.
    private var activeTouches: [Touch: KeyRegistration] = [:]

    /// Number of currently tracked touches.
    var activeTouchCount: Int { activeTouches.count }

    func touchBegan(_ touch: Touch, key: KeyRegistration) {
        activeTouches[touch] = key
        onPress?(key.keyName, key.keyType)
    }

    func touchMoved(_ touch: Touch, point: CGPoint) {
        guard let reg = activeTouches[touch] else { return }
        onMoved?(point, reg.keyName)
    }

    func touchEnded(_ touch: Touch) {
        guard let reg = activeTouches.removeValue(forKey: touch) else { return }
        onRelease?(reg.keyName, reg.keyType)
    }

    /// Cancel all active touches, firing onRelease for each.
    func cancelAll() {
        let allTouches = activeTouches
        activeTouches.removeAll()
        for (_, reg) in allTouches {
            onRelease?(reg.keyName, reg.keyType)
        }
    }

    /// Get the key registration for a specific touch.
    func key(for touch: Touch) -> KeyRegistration? {
        activeTouches[touch]
    }
}
