import SwiftUI

/// Top toolbar showing connection status and controls
struct TerminalToolbar: View {
    let status: TerminalViewModel.ConnectionStatus
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onToggleSpecialKeys: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Connection status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Special keys toggle
            Button(action: onToggleSpecialKeys) {
                Image(systemName: "keyboard")
                    .foregroundColor(ThemeManager.shared.accentColor)
            }

            // Connect/Disconnect button
            if status == .connected {
                Button(action: onDisconnect) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                }
            } else {
                Button(action: onConnect) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(ThemeManager.shared.accentColor)
                }
                .disabled(status == .connecting)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(.secondary.opacity(0.3)),
            alignment: .bottom
        )
    }

    private var statusColor: Color {
        switch status {
        case .disconnected:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch status {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }
}
