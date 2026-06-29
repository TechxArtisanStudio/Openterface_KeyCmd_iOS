import SwiftUI

/// Material Symbols `keyboard_arrow_*_24` caret, normalized from the 960×960 viewport.
/// Matches the Android `@drawable/keyboard_arrow_{up,down,left,right}_24` paths.
struct KeyboardArrow: Shape {
    enum Direction { case up, down, left, right }
    var direction: Direction

    // Paths are given in the canonical 960×960 viewport; normalized to 0...1 below.
    private static let up: [CGPoint] = [
        .init(x: 480, y: 432), .init(x: 296, y: 616), .init(x: 240, y: 560),
        .init(x: 480, y: 320), .init(x: 720, y: 560), .init(x: 664, y: 616)
    ]
    private static let down: [CGPoint] = [
        .init(x: 480, y: 616), .init(x: 240, y: 376), .init(x: 296, y: 320),
        .init(x: 480, y: 504), .init(x: 664, y: 320), .init(x: 720, y: 376)
    ]
    private static let left: [CGPoint] = [
        .init(x: 560, y: 720), .init(x: 320, y: 480), .init(x: 560, y: 240),
        .init(x: 616, y: 296), .init(x: 432, y: 480), .init(x: 616, y: 664)
    ]
    private static let right: [CGPoint] = [
        .init(x: 504, y: 480), .init(x: 320, y: 296), .init(x: 376, y: 240),
        .init(x: 616, y: 480), .init(x: 376, y: 720), .init(x: 320, y: 664)
    ]

    func path(in rect: CGRect) -> Path {
        let points: [CGPoint]
        switch direction {
        case .up:    points = Self.up
        case .down:  points = Self.down
        case .left:  points = Self.left
        case .right: points = Self.right
        }
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x / 960 * rect.width,
                              y: rect.minY + first.y / 960 * rect.height))
        for p in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + p.x / 960 * rect.width,
                                     y: rect.minY + p.y / 960 * rect.height))
        }
        path.closeSubpath()
        return path
    }
}
