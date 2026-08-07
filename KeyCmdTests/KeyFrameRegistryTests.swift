import XCTest
import SwiftUI
@testable import KeyCmd

final class KeyFrameRegistryTests: XCTestCase {

    func testKeyTypeModifier() {
        let reg = KeyRegistration(
            keyId: "cmd_left",
            keyName: "Cmd",
            keyType: .modifier,
            frame: CGRect(x: 0, y: 0, width: 50, height: 40)
        )
        XCTAssertEqual(reg.keyType, .modifier)
        XCTAssertEqual(reg.keyName, "Cmd")
    }

    func testKeyTypeRegular() {
        let reg = KeyRegistration(
            keyId: "tab",
            keyName: "Tab",
            keyType: .regular,
            frame: CGRect(x: 0, y: 0, width: 50, height: 40)
        )
        XCTAssertEqual(reg.keyType, .regular)
    }

    func testKeyTypeSpecial() {
        let reg = KeyRegistration(
            keyId: "caps",
            keyName: "Caps",
            keyType: .special,
            frame: CGRect(x: 0, y: 0, width: 50, height: 40)
        )
        XCTAssertEqual(reg.keyType, .special)
    }

    func testHitTestInsideKey() {
        let registry = KeyFrameRegistry()
        registry.register(KeyRegistration(
            keyId: "tab",
            keyName: "Tab",
            keyType: .regular,
            frame: CGRect(x: 10, y: 20, width: 50, height: 40)
        ))
        let result = registry.hitTest(CGPoint(x: 30, y: 35))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.keyName, "Tab")
    }

    func testHitTestOutsideKey() {
        let registry = KeyFrameRegistry()
        registry.register(KeyRegistration(
            keyId: "tab",
            keyName: "Tab",
            keyType: .regular,
            frame: CGRect(x: 10, y: 20, width: 50, height: 40)
        ))
        let result = registry.hitTest(CGPoint(x: 100, y: 100))
        XCTAssertNil(result)
    }

    func testHitTestMultipleKeys() {
        let registry = KeyFrameRegistry()
        registry.register(KeyRegistration(
            keyId: "cmd",
            keyName: "Cmd",
            keyType: .modifier,
            frame: CGRect(x: 0, y: 0, width: 50, height: 40)
        ))
        registry.register(KeyRegistration(
            keyId: "tab",
            keyName: "Tab",
            keyType: .regular,
            frame: CGRect(x: 60, y: 0, width: 50, height: 40)
        ))
        let cmdHit = registry.hitTest(CGPoint(x: 25, y: 20))
        XCTAssertEqual(cmdHit?.keyName, "Cmd")
        let tabHit = registry.hitTest(CGPoint(x: 80, y: 20))
        XCTAssertEqual(tabHit?.keyName, "Tab")
    }

    func testHitTestLastRegisteredWins() {
        // When two keys overlap (shouldn't happen, but defensive), later registration wins
        let registry = KeyFrameRegistry()
        registry.register(KeyRegistration(
            keyId: "a", keyName: "A", keyType: .regular,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        ))
        registry.register(KeyRegistration(
            keyId: "b", keyName: "B", keyType: .regular,
            frame: CGRect(x: 50, y: 50, width: 100, height: 100)
        ))
        let result = registry.hitTest(CGPoint(x: 75, y: 75))
        XCTAssertEqual(result?.keyName, "B")
    }

    func testClearRegistrations() {
        let registry = KeyFrameRegistry()
        registry.register(KeyRegistration(
            keyId: "a", keyName: "A", keyType: .regular,
            frame: CGRect(x: 0, y: 0, width: 50, height: 40)
        ))
        registry.clear()
        let result = registry.hitTest(CGPoint(x: 25, y: 20))
        XCTAssertNil(result)
    }

    func testComputeFramesForSimpleGrid() {
        // 2 rows × 3 keys, equal width, spacing 3, padding 0
        let layout = KeyboardLayoutDescription(
            rows: [
                ["A", "B", "C"],
                ["D", "E", "F"]
            ],
            containerSize: CGSize(width: 306, height: 206), // 3 keys × 100 + 2×3 spacing = 306; 2 rows × 100 + 1×6 spacing = 206
            rowSpacing: 6,
            keySpacing: 3,
            padding: EdgeInsets(),
            fixedRowHeights: [],
            fixedKeyWidths: [:]
        )
        let registry = KeyFrameRegistry()
        registry.computeFrames(from: layout, keyTypeResolver: { _ in .regular })

        // Key "A" should be at (0, 0) with size 100×100
        let aHit = registry.hitTest(CGPoint(x: 50, y: 50))
        XCTAssertEqual(aHit?.keyName, "A")

        // Key "B" should be at (103, 0) — after A (100) + spacing (3)
        let bHit = registry.hitTest(CGPoint(x: 150, y: 50))
        XCTAssertEqual(bHit?.keyName, "B")

        // Key "D" should be at (0, 106) — after row 1 (100) + spacing (6)
        let dHit = registry.hitTest(CGPoint(x: 50, y: 150))
        XCTAssertEqual(dHit?.keyName, "D")
    }

    func testComputeFramesWithPadding() {
        let layout = KeyboardLayoutDescription(
            rows: [["X"]],
            containerSize: CGSize(width: 116, height: 58),
            rowSpacing: 6,
            keySpacing: 3,
            padding: EdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 0),
            fixedRowHeights: [],
            fixedKeyWidths: [:]
        )
        let registry = KeyFrameRegistry()
        registry.computeFrames(from: layout, keyTypeResolver: { _ in .regular })

        // Key "X" should be at (8, 8) after padding, size 100×42
        let xHit = registry.hitTest(CGPoint(x: 50, y: 25))
        XCTAssertEqual(xHit?.keyName, "X")
        // Outside padding should not hit
        let miss = registry.hitTest(CGPoint(x: 2, y: 2))
        XCTAssertNil(miss)
    }

    func testComputeFramesWithFixedRowHeights() {
        // 2 rows: first row fixed at 30pt, second row fills remaining
        let layout = KeyboardLayoutDescription(
            rows: [["A", "B"], ["C", "D"]],
            containerSize: CGSize(width: 203, height: 136), // 200 + 3 spacing = 203; 30 + 6 + 100 = 136
            rowSpacing: 6,
            keySpacing: 3,
            padding: EdgeInsets(),
            fixedRowHeights: [30], // first row is 30pt
            fixedKeyWidths: [:]
        )
        let registry = KeyFrameRegistry()
        registry.computeFrames(from: layout, keyTypeResolver: { _ in .regular })

        // Row 1 at y=0..30
        let aHit = registry.hitTest(CGPoint(x: 50, y: 15))
        XCTAssertEqual(aHit?.keyName, "A")

        // Row 2 at y=36..136 (30 + 6 spacing)
        let cHit = registry.hitTest(CGPoint(x: 50, y: 80))
        XCTAssertEqual(cHit?.keyName, "C")
    }
}
