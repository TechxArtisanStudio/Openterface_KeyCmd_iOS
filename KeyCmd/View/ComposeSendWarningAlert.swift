import SwiftUI

struct ComposeSendWarningAlert: View {
    let text: String
    let warningInfo: ComposeSendGate.WarningInfo
    @Binding var unicodeMode: Bool
    let onSendAnyway: () -> Void
    let onSendUnicode: () -> Void
    let onCheck: () -> Void
    let onPreview: () -> Void

    private var primaryActionLabel: String {
        unicodeMode ? "Send via Unicode" : "Send Anyway"
    }

    private var primaryActionIcon: String {
        unicodeMode ? "character.cursor.ibeam" : "paperplane.fill"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with mode toggle
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text("Send Check")
                    .font(.headline)
                Spacer()

                // Mode switch icon — only show when there are non-ASCII chars
                if warningInfo.hasNonAscii {
                    Button(action: { unicodeMode.toggle() }) {
                        Image(systemName: unicodeMode ? "character.cursor.ibeam" : "keyboard")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Characters").bold()
                    Text(": \(warningInfo.charCount)")
                }
                .font(.subheadline)

                if warningInfo.hasNonAscii || warningInfo.hasLengthRisk {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").bold()
                            .font(.subheadline)
                            .padding(.bottom, 2)

                        if warningInfo.hasNonAscii {
                            if unicodeMode {
                                Label("Unicode mode: Send all characters via host HID encoding", systemImage: "character.cursor.ibeam")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            } else {
                                Label("Non-ASCII characters: Unprintable characters will be dropped", systemImage: "character.cursor.ibeam")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if warningInfo.hasLengthRisk {
                            Label("Long text: Sending may take longer", systemImage: "clock")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(16)

            Divider()

            // Action buttons
            VStack(spacing: 0) {
                // Secondary actions row
                if warningInfo.hasNonAscii {
                    HStack(spacing: 16) {
                        Button(action: onCheck) {
                            Label("Check", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)

                        Button(action: onPreview) {
                            Label("Preview", systemImage: "eye")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                    Divider()
                }

                // Primary action
                Button(action: unicodeMode ? onSendUnicode : onSendAnyway) {
                    Label(primaryActionLabel, systemImage: primaryActionIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .foregroundColor(unicodeMode ? .purple : .blue)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .background(Color(UIColor.secondarySystemBackground))
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(unicodeMode ? Color.purple : Color.clear, lineWidth: 2)
        )
    }
}
