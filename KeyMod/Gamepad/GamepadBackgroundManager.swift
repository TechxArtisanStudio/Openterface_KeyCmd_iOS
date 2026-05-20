//
//  GamepadBackgroundManager.swift
//  KeyMod
//
//  Manages gamepad background: solid color, gradient, pattern overlay, and custom image.
//  Supports pan/zoom gestures on background images.
//

import Foundation
import Combine
import SwiftUI
import UIKit

enum BackgroundType: String, Codable, CaseIterable {
    case solidColor = "Solid Color"
    case gradient = "Gradient"
    case pattern = "Pattern"
    case image = "Custom Image"
}

class GamepadBackgroundManager: ObservableObject {
    @Published var backgroundType: BackgroundType = .gradient
    @Published var solidColorHex: String = "#1a1a2e"
    @Published var gradientTopHex: String = "#F5F5F5"
    @Published var gradientBottomHex: String = "#ECECEC"
    @Published var pattern: BackgroundPattern = .none
    @Published var imageFileName: String?

    // Pan/zoom state
    @Published var bgScale: CGFloat = 1.0
    @Published var bgOffsetX: CGFloat = 0
    @Published var bgOffsetY: CGFloat = 0

    // Loaded image
    @Published var backgroundImage: UIImage?

    private let userDefaults = UserDefaults.standard
    private let configKey = "GamepadBackgroundConfig"
    private let stateKey = "GamepadBackgroundState"

    private var imagesDirectory: URL {
        let container = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return container.appendingPathComponent("GamepadBackgrounds", conformingTo: .directory)
    }

    init() {
        // Create images directory
        do {
            try FileManager.default.createDirectory(
                at: imagesDirectory, withIntermediateDirectories: true
            )
        } catch {}

        loadConfig()
        loadImage()
    }

    // MARK: - Image Management

    func setImage(_ image: UIImage) {
        let fileName = UUID().uuidString + ".jpg"
        let url = imagesDirectory.appendingPathComponent(fileName)

        guard let data = image.jpegData(compressionQuality: 0.85) else { return }

        do {
            try data.write(to: url)
            imageFileName = fileName
            backgroundImage = image
            backgroundType = .image
            bgScale = 1.0
            bgOffsetX = 0
            bgOffsetY = 0
            saveConfig()
        } catch {
            print("⚠️ Failed to save background image: \(error)")
        }
    }

    func removeImage() {
        if let fileName = imageFileName {
            let url = imagesDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
        imageFileName = nil
        backgroundImage = nil
        saveConfig()
    }

    func applyPanOffset(_ offset: CGSize) {
        bgOffsetX = offset.width
        bgOffsetY = offset.height
    }

    func applyZoom(_ scale: CGFloat) {
        bgScale = max(0.5, min(3.0, scale))
    }

    func resetTransform() {
        bgScale = 1.0
        bgOffsetX = 0
        bgOffsetY = 0
    }

    // MARK: - Persistence

    func saveConfig() {
        let config = BackgroundConfigData(
            type: backgroundType,
            solidColorHex: solidColorHex,
            gradientTopHex: gradientTopHex,
            gradientBottomHex: gradientBottomHex,
            pattern: pattern,
            imageFileName: imageFileName,
            bgScale: bgScale,
            bgOffsetX: bgOffsetX,
            bgOffsetY: bgOffsetY
        )
        if let data = try? JSONEncoder().encode(config) {
            userDefaults.set(data, forKey: configKey)
        }
    }

    private func loadConfig() {
        guard let data = userDefaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(BackgroundConfigData.self, from: data) else {
            return
        }
        backgroundType = config.type
        solidColorHex = config.solidColorHex
        gradientTopHex = config.gradientTopHex
        gradientBottomHex = config.gradientBottomHex
        pattern = config.pattern
        imageFileName = config.imageFileName
        bgScale = config.bgScale
        bgOffsetX = config.bgOffsetX
        bgOffsetY = config.bgOffsetY
    }

    private func loadImage() {
        guard let fileName = imageFileName else { return }
        let url = imagesDirectory.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            backgroundImage = image
        }
    }
}

// MARK: - Background Config Data (for persistence)

struct BackgroundConfigData: Codable {
    var type: BackgroundType
    var solidColorHex: String
    var gradientTopHex: String
    var gradientBottomHex: String
    var pattern: BackgroundPattern
    var imageFileName: String?
    var bgScale: CGFloat
    var bgOffsetX: CGFloat
    var bgOffsetY: CGFloat
}

// MARK: - Background Pattern Drawing

struct BackgroundPatternRenderer: View {
    let pattern: BackgroundPattern
    let size: CGSize
    let isLight: Bool

    var body: some View {
        Canvas { context, canvasSize in
            let density: CGFloat = 1.0
            let strokeColor: Color = isLight ? .black.opacity(0.07) : .white.opacity(0.07)

            switch pattern {
            case .none:
                break
            case .dots:
                let spacing: CGFloat = 24
                let radius: CGFloat = 0.35 * spacing
                var x: CGFloat = 0
                while x < canvasSize.width {
                    var y: CGFloat = 0
                    while y < canvasSize.height {
                        context.fill(
                            Circle().path(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(strokeColor)
                        )
                        y += spacing
                    }
                    x += spacing
                }
            case .microGrid:
                let spacing: CGFloat = 14
                var gridPath = Path()
                var x: CGFloat = 0
                while x < canvasSize.width {
                    gridPath.move(to: CGPoint(x: x, y: 0))
                    gridPath.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y < canvasSize.height {
                    gridPath.move(to: CGPoint(x: 0, y: y))
                    gridPath.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    y += spacing
                }
                context.stroke(gridPath, with: .color(strokeColor), lineWidth: 0.5)
            case .diagonalHatch:
                let spacing: CGFloat = 18
                var hatchPath = Path()
                let totalSize = max(canvasSize.width, canvasSize.height)
                for offset in stride(from: -totalSize, to: totalSize * 2, by: spacing) {
                    hatchPath.move(to: CGPoint(x: offset, y: 0))
                    hatchPath.addLine(to: CGPoint(x: offset + totalSize, y: totalSize))
                }
                context.stroke(hatchPath, with: .color(strokeColor), lineWidth: 0.5)
            case .noise:
                let seed: UInt64 = 42
                var rng = SeededRandom(seed)
                for _ in 0..<500 {
                    let x = CGFloat(rng.next()) * canvasSize.width
                    let y = CGFloat(rng.next()) * canvasSize.height
                    context.fill(
                        Circle().path(in: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(strokeColor)
                    )
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Seeded Random

struct SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1
        return Double(state &>> 33) / Double(1 << 31)
    }
}

// MARK: - Background Renderer View

struct GamepadBackgroundRenderer: View {
    @ObservedObject var manager: GamepadBackgroundManager

    var body: some View {
        ZStack {
            switch manager.backgroundType {
            case .solidColor:
                Color(hex: manager.solidColorHex)
            case .gradient:
                LinearGradient(
                    colors: [Color(hex: manager.gradientTopHex), Color(hex: manager.gradientBottomHex)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .pattern:
                Color(hex: manager.gradientTopHex)
                    .overlay(
                        BackgroundPatternRenderer(
                            pattern: manager.pattern,
                            size: .init(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height),
                            isLight: isLightColor(hex: manager.gradientTopHex)
                        )
                    )
            case .image:
                if let image = manager.backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(manager.bgScale)
                        .offset(x: manager.bgOffsetX, y: manager.bgOffsetY)
                } else {
                    Color(hex: manager.gradientTopHex)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func isLightColor(hex: String) -> Bool {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return (r * 0.299 + g * 0.587 + b * 0.114) > 0.5
    }
}
