import SwiftUI
import SwiftTerm

/// SwiftUI wrapper for SwiftTerm's AppleTerminalView (UIKit)
struct TerminalCanvas: UIViewRepresentable {
    @ObservedObject var viewModel: TerminalViewModel

    func makeUIView(context: Context) -> TerminalView {
        let terminalView = TerminalView(frame: .zero)
        viewModel.emulator.attach(to: terminalView)
        return terminalView
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // Update view if needed
    }
}
