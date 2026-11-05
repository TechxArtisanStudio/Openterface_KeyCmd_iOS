import SwiftUI

/// SwiftUI wrapper for MultiTouchKeyboardContainerView.
/// Exposes the key registry and event callbacks to SwiftUI views.
struct MultiTouchKeyboardContainer: UIViewRepresentable {

    /// Layout description for computing key frames.
    let layout: KeyboardLayoutDescription
    /// Frames measured from the rendered key views. Empty until the first layout pass.
    let measuredFrames: [KeyRegistration]
    /// Maps key names to their KeyType.
    let keyTypeResolver: (String) -> KeyType
    /// Called when a key is pressed.
    let onPress: (String, KeyType) -> Void
    /// Called when a key is released.
    let onRelease: (String, KeyType) -> Void
    /// Called when a touch moves (for slide-to-lock detection).
    let onMoved: (CGPoint, String) -> Void

    func makeUIView(context: Context) -> MultiTouchKeyboardContainerView {
        let view = MultiTouchKeyboardContainerView()
        view.onPress = onPress
        view.onRelease = onRelease
        view.onMoved = onMoved
        syncFrames(into: view)
        return view
    }

    func updateUIView(_ uiView: MultiTouchKeyboardContainerView, context: Context) {
        // Update callbacks (they may capture changing state)
        uiView.onPress = onPress
        uiView.onRelease = onRelease
        uiView.onMoved = onMoved
        // Recompute frames when layout changes (rotation, resize)
        syncFrames(into: uiView)
    }

    private func syncFrames(into view: MultiTouchKeyboardContainerView) {
        if measuredFrames.isEmpty {
            view.registry.computeFrames(from: layout, keyTypeResolver: keyTypeResolver)
        } else {
            view.registry.setRegistrations(measuredFrames)
        }
    }
}
