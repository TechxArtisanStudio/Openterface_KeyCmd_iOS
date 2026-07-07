import SwiftUI

/// SSH connection dialog
struct ConnectionDialog: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TerminalViewModel

    @State private var host = "192.168.11.2"
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Server") {
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }

                Section("Authentication") {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                }

                if case .error(let msg) = viewModel.connectionStatus {
                    Section {
                        Text(msg)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        Task {
                            if let portInt = Int(port) {
                                await viewModel.connect(
                                    host: host,
                                    port: portInt,
                                    username: username,
                                    password: password
                                )
                            }
                        }
                    }
                    .disabled(host.isEmpty || username.isEmpty ||
                              viewModel.connectionStatus == .connecting)
                }
            }
        }
    }
}
