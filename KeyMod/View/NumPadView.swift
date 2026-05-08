import SwiftUI

struct NumPadView: View {
    @ObservedObject var keyboardManager: KeyboardManager
    @ObservedObject var orientationManager: OrientationManager
    @StateObject private var hapticManager = HapticFeedbackManager.shared
    // Layout for a standard 101-key numpad
    private let numpadKeys: [[String?]] = [
        ["Num Lock", "/", "*"],
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
        ["0", ".", nil]
    ]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 4) {
                    ForEach(0..<numpadKeys.count, id: \.self) { row in
                        HStack(spacing: 4) {
                            if row == 4 {
                                // Zero key spans two columns
                                Button(action: {
                                    hapticManager.triggerButtonPress()
                                    keyboardManager.handleKeyPress("0")
                                }) {
                                    Text("0")
                                        .font(.system(size: min(geometry.size.width, geometry.size.height) / 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(
                                            width: keyWidth(for: geometry) * 2 + 4,
                                            height: keyHeight(for: geometry)
                                        )
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(6)
                                }
                                // Dot key
                                if let dot = numpadKeys[row][1] {
                                    Button(action: {
                                        hapticManager.triggerButtonPress()
                                        keyboardManager.handleKeyPress(dot)
                                    }) {
                                        Text(dot)
                                            .font(.system(size: min(geometry.size.width, geometry.size.height) / 14, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(
                                                width: keyWidth(for: geometry),
                                                height: keyHeight(for: geometry)
                                            )
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(6)
                                    }
                                } else {
                                    Spacer().frame(width: keyWidth(for: geometry))
                                }
                            } else {
                                ForEach(0..<3, id: \.self) { col in
                                    if let key = numpadKeys[row][col] {
                                        Button(action: {
                                            hapticManager.triggerButtonPress()
                                            keyboardManager.handleKeyPress(key)
                                        }) {
                                            Text(key)
                                                .font(.system(size: min(geometry.size.width, geometry.size.height) / 14, weight: .bold))
                                                .foregroundColor(.white)
                                                .frame(
                                                    width: keyWidth(for: geometry),
                                                    height: keyHeight(for: geometry)
                                                )
                                                .background(Color.gray.opacity(0.2))
                                                .cornerRadius(6)
                                        }
                                    } else {
                                        Spacer().frame(width: keyWidth(for: geometry))
                                    }
                                }
                            }
                        }
                    }
                }
                VStack(spacing: 4) {
                    // Minus key
                    Button(action: {
                        hapticManager.triggerButtonPress()
                        keyboardManager.handleKeyPress("-")
                    }) {
                        Text("-")
                            .font(.system(size: min(geometry.size.width, geometry.size.height) / 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(
                                width: keyWidth(for: geometry),
                                height: keyHeight(for: geometry)
                            )
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                    // Plus key
                    Button(action: {
                        hapticManager.triggerButtonPress()
                        keyboardManager.handleKeyPress("+")
                    }) {
                        Text("+")
                            .font(.system(size: min(geometry.size.width, geometry.size.height) / 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(
                                width: keyWidth(for: geometry),
                                height: keyHeight(for: geometry)
                            )
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                    // Backspace key
                    Button(action: {
                        hapticManager.triggerButtonPress()
                        keyboardManager.handleKeyPress("Backspace")
                    }) {
                        Image(systemName: "delete.left")
                            .font(.system(size: min(geometry.size.width, geometry.size.height) / 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(
                                width: keyWidth(for: geometry),
                                height: keyHeight(for: geometry)
                            )
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                    // Enter key spans two rows
                    Button(action: {
                        hapticManager.triggerButtonPress()
                        keyboardManager.handleKeyPress("Enter")
                    }) {
                        Text("Enter")
                            .font(.system(size: min(geometry.size.width, geometry.size.height) / 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(
                                width: keyWidth(for: geometry),
                                height: keyHeight(for: geometry) * 2 + 4
                            )
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
            .padding(.leading, orientationManager.isLandscape ? max(geometry.safeAreaInsets.leading, 45) : 0)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray, lineWidth: 1)
            )
        }
        .edgesIgnoringSafeArea(.all)
    }

    private func keyWidth(for geometry: GeometryProxy) -> CGFloat {
        geometry.size.width / 4 - 8
    }

    private func keyHeight(for geometry: GeometryProxy) -> CGFloat {
        geometry.size.height / 6 - 8
    }
}

struct NumPadView_Previews: PreviewProvider {
    static var previews: some View {
        let orientationManager = OrientationManager()
        return NumPadView(keyboardManager: KeyboardManager(bleManager: BLEManager()), orientationManager: orientationManager)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
