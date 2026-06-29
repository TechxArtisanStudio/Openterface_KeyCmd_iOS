import SwiftUI

/// Bottom bar with common terminal control keys
struct TerminalBottomBar: View {
    let viewModel: TerminalViewModel

    var body: some View {
        HStack(spacing: 0) {
            SpecialKeyButton(label: "Ctrl", action: { viewModel.sendSpecialKey(.ctrlC) })

            Divider().frame(height: 24)

            SpecialKeyButton(label: "Esc", action: { viewModel.sendSpecialKey(.escape) })

            Divider().frame(height: 24)

            SpecialKeyButton(label: "Tab", action: { viewModel.sendSpecialKey(.tab) })

            Divider().frame(height: 24)

            SpecialKeyButton(label: "\u{2190}", action: { viewModel.sendSpecialKey(.leftArrow) })

            SpecialKeyButton(label: "\u{2191}", action: { viewModel.sendSpecialKey(.upArrow) })

            SpecialKeyButton(label: "\u{2193}", action: { viewModel.sendSpecialKey(.downArrow) })

            SpecialKeyButton(label: "\u{2192}", action: { viewModel.sendSpecialKey(.rightArrow) })

            Spacer()

            if viewModel.connectionStatus == .connected {
                Button(action: { viewModel.disconnect() }) {
                    Text("Disconnect")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
    }
}

struct SpecialKeyButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.monospaced())
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .cornerRadius(4)
        }
        .padding(.horizontal, 2)
    }
}