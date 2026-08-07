import XCTest
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
}
