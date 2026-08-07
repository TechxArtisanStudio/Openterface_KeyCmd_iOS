import CoreGraphics

/// Stores key registrations and performs coordinate-based hit-testing.
/// Thread-safe: all access is on the main thread (UI touch events).
final class KeyFrameRegistry {
    private var registrations: [KeyRegistration] = []

    func register(_ registration: KeyRegistration) {
        registrations.append(registration)
    }

    func clear() {
        registrations.removeAll()
    }

    /// Returns the key at the given point, or nil if no key contains the point.
    /// If multiple keys overlap, the last registered key wins.
    func hitTest(_ point: CGPoint) -> KeyRegistration? {
        // Iterate in reverse so later registrations (drawn on top) take priority
        for reg in registrations.reversed() {
            if reg.frame.contains(point) {
                return reg
            }
        }
        return nil
    }

    /// All currently registered keys.
    var allKeys: [KeyRegistration] { registrations }
}
