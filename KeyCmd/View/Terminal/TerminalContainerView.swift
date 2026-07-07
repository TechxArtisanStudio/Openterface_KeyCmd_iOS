import SwiftUI

/// Container view for the terminal - manages state and UI composition
struct TerminalContainerView: View {
    @StateObject private var viewModel: TerminalViewModel
    @State private var showConnectionDialog = false
    @State private var showSpecialKeys = false
    @State private var keyboardHeight: CGFloat = 0

    init(bleManager: BLEManager) {
        _viewModel = StateObject(wrappedValue: TerminalViewModel(bleManager: bleManager))
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalToolbar(
                status: viewModel.connectionStatus,
                onConnect: { showConnectionDialog = true },
                onDisconnect: { viewModel.disconnect() },
                onToggleSpecialKeys: { showSpecialKeys.toggle() }
            )

            TerminalCanvas(viewModel: viewModel)
                .padding(.bottom, keyboardHeight)

            if showSpecialKeys {
                TerminalBottomBar(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showConnectionDialog) {
            ConnectionDialog(viewModel: viewModel)
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = keyboardFrame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }
}
