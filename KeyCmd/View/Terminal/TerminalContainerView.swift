import SwiftUI

/// Container view for the terminal - manages state and UI composition
struct TerminalContainerView: View {
    @ObservedObject var viewModel: TerminalViewModel
    @State private var showConnectionDialog = false
    @State private var showSpecialKeys = false
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            TerminalToolbar(
                status: viewModel.connectionStatus,
                onConnect: { showConnectionDialog = true },
                onDisconnect: { viewModel.disconnect() },
                onToggleSpecialKeys: { showSpecialKeys.toggle() }
            )

            ZStack {
                TerminalCanvas(viewModel: viewModel)
                    .padding(.bottom, keyboardHeight)

                // Connection overlay (shown when disconnected, like Android)
                if viewModel.connectionStatus == .disconnected {
                    connectionOverlay
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.connectionStatus)

            if showSpecialKeys {
                TerminalBottomBar(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showConnectionDialog) {
            ConnectionDialog(viewModel: viewModel)
        }
        .navigationTitle(NSLocalizedString("terminal_title", comment: "Terminal view title"))
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
        .onAppear {
            CredentialManager.shared.ensureDefaultKeyCmdProfile()
        }
    }

    // MARK: - Connection Overlay

    private var connectionOverlay: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(NSLocalizedString("terminal_title", comment: "Terminal view title"))
                .font(.title2.bold())
                .foregroundColor(.primary)

            Text(NSLocalizedString("terminal_connect_prompt", comment: "Terminal connect prompt"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // CDC-ECM transport notice
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "network")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(NSLocalizedString(
                    "terminal_cdc_ecm_notice",
                    value: "KeyMod device uses CDC-ECM mode — works with Linux and macOS without drivers. Windows RNDIS support is coming soon.",
                    comment: "CDC-ECM transport notice for terminal connect screen"
                ))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            .padding(.top, 2)

            Button(action: { showConnectionDialog = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Connect via BLE")
                }
                .font(.subheadline.bold())
                .frame(width: 200, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.95))
    }
}
