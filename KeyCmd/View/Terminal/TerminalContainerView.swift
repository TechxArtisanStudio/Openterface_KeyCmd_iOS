import SwiftUI

/// Container view for the terminal - manages state and UI composition
struct TerminalContainerView: View {
    @StateObject private var viewModel: TerminalViewModel
    @State private var showConnectionDialog = false
    @State private var showSpecialKeys = false

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

            if showSpecialKeys {
                TerminalBottomBar(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showConnectionDialog) {
            ConnectionDialog(viewModel: viewModel)
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
    }
}
