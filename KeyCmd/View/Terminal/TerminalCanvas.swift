import SwiftUI
import SwiftTerm

/// SwiftUI wrapper for SwiftTerm's TerminalView (UIKit)
/// Supports pinch-to-zoom for font size adjustment.
struct TerminalCanvas: UIViewRepresentable {
    @ObservedObject var viewModel: TerminalViewModel

    func makeUIView(context: Context) -> TerminalView {
        // Use a reasonable initial frame so TerminalView has dimensions before SwiftUI layout kicks in.
        // Without this, feed() called during SSH connect renders into a 0×0 grid and produces blank screen.
        let initialFrame = UIScreen.main.bounds.inset(by: UIEdgeInsets(top: 120, left: 0, bottom: 0, right: 0))
        let terminalView = TerminalView(frame: initialFrame)
        viewModel.emulator.attach(to: terminalView)

        // Apply persisted font size
        let fontSize = TerminalPrefs.shared.fontSize
        terminalView.font = UIFont(name: "Menlo", size: fontSize)
            ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Add pinch-to-zoom via UIGestureRecognizer
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        terminalView.addGestureRecognizer(pinch)
        context.coordinator.terminalView = terminalView

        return terminalView
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // Update view if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        weak var terminalView: TerminalView?
        private var baseFontSize: CGFloat = 0

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let tv = terminalView else { return }

            switch gesture.state {
            case .began:
                baseFontSize = tv.font.pointSize

            case .changed:
                let newSize = max(10, min(32, baseFontSize * gesture.scale))
                tv.font = UIFont(name: "Menlo", size: newSize)
                    ?? UIFont.monospacedSystemFont(ofSize: newSize, weight: .regular)

            case .ended, .cancelled:
                // Persist the final font size
                TerminalPrefs.shared.fontSize = tv.font.pointSize

            default:
                break
            }
        }
    }
}
