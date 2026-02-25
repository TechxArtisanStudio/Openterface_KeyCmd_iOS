import SwiftUI

struct NumPadView: View {
    @ObservedObject var keyboardManager: KeyboardManager
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
            let keyWidth = geometry.size.width / 4 - 8
            let keyHeight = geometry.size.height / 5 - 8
            HStack(spacing: 4) {
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
                                            width: keyWidth * 2 + 4, // span two columns
                                            height: keyHeight
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
                                                width: keyWidth,
                                                height: keyHeight
                                            )
                                            .background(Color.gray.opacity(0.2))
                                            .cornerRadius(6)
                                    }
                                } else {
                                    Spacer().frame(width: keyWidth)
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
                                                    width: keyWidth,
                                                    height: keyHeight
                                                )
                                                .background(Color.gray.opacity(0.2))
                                                .cornerRadius(6)
                                        }
                                    } else {
                                        Spacer().frame(width: keyWidth)
                                    }
                                }
                            }
                        }
                    }
                }
                VStack(spacing: 4) {
                    // Minus key (top right) aligned with first row
                    Spacer().frame(height: 0)
                    Button(action: {
                        hapticManager.triggerButtonPress()
                        keyboardManager.handleKeyPress("-")
                    }) {
                        Text("-")
                            .font(.system(size: min(geometry.size.width, geometry.size.height) / 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(
                                width: keyWidth,
                                height: keyHeight
                            )
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                    // Plus key spans two rows
                    Button(action: {
                        hapticManager.triggerButtonPress()
                        keyboardManager.handleKeyPress("+")
                    }) {
                        Text("+")
                            .font(.system(size: min(geometry.size.width, geometry.size.height) / 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(
                                width: keyWidth,
                                height: keyHeight * 2 + 4 // span two rows
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
                                width: keyWidth,
                                height: keyHeight * 2 + 4 // span two rows
                            )
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                    Spacer()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray, lineWidth: 1)
            )
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct NumPadView_Previews: PreviewProvider {
    static var previews: some View {
        NumPadView(keyboardManager: KeyboardManager(bleManager: BLEManager()))
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
