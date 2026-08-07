import UIKit

/// UIKit view that handles multi-touch for the keyboard.
/// Overrides touchesBegan/Moved/Ended/Cancelled to dispatch key events.
/// Must have `isMultipleTouchEnabled = true`.
final class MultiTouchKeyboardContainerView: UIView {

    let registry = KeyFrameRegistry()
    private let tracker = TouchTracker<UITouch>()

    /// Called when a key is pressed. (keyName, keyType)
    var onPress: ((String, KeyType) -> Void)?
    /// Called when a key is released. (keyName, keyType)
    var onRelease: ((String, KeyType) -> Void)?
    /// Called when a touch moves. (point, keyName)
    var onMoved: ((CGPoint, String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isUserInteractionEnabled = true

        tracker.onPress = { [weak self] keyName, keyType in
            self?.onPress?(keyName, keyType)
        }
        tracker.onRelease = { [weak self] keyName, keyType in
            self?.onRelease?(keyName, keyType)
        }
        tracker.onMoved = { [weak self] point, keyName in
            self?.onMoved?(point, keyName)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if let key = registry.hitTest(point) {
                tracker.touchBegan(touch, key: key)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            tracker.touchMoved(touch, point: point)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            tracker.touchEnded(touch)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            tracker.touchEnded(touch) // treat cancellation same as release
        }
    }
}
