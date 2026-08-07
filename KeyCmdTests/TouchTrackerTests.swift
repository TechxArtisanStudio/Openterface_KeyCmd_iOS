import XCTest
import CoreGraphics
@testable import KeyCmd

final class TouchTrackerTests: XCTestCase {

    func testInitialActiveCountIsZero() {
        let tracker = TouchTracker<MockTouch>()
        XCTAssertEqual(tracker.activeTouchCount, 0)
    }

    func testRegisterTouchFiresPress() {
        let tracker = TouchTracker<MockTouch>()
        var pressedKeys: [String] = []
        tracker.onPress = { keyName, _ in pressedKeys.append(keyName) }

        let touch = MockTouch(id: 1)
        let reg = KeyRegistration(keyId: "tab", keyName: "Tab", keyType: .regular, frame: .zero)
        tracker.touchBegan(touch, key: reg)

        XCTAssertEqual(tracker.activeTouchCount, 1)
        XCTAssertEqual(pressedKeys, ["Tab"])
    }

    func testUnregisterTouchFiresRelease() {
        let tracker = TouchTracker<MockTouch>()
        var releasedKeys: [String] = []
        tracker.onRelease = { keyName, _ in releasedKeys.append(keyName) }

        let touch = MockTouch(id: 1)
        let reg = KeyRegistration(keyId: "tab", keyName: "Tab", keyType: .regular, frame: .zero)
        tracker.touchBegan(touch, key: reg)
        tracker.touchEnded(touch)

        XCTAssertEqual(tracker.activeTouchCount, 0)
        XCTAssertEqual(releasedKeys, ["Tab"])
    }

    func testMultipleSimultaneousTouches() {
        let tracker = TouchTracker<MockTouch>()
        var pressedKeys: [String] = []
        var releasedKeys: [String] = []
        tracker.onPress = { keyName, _ in pressedKeys.append(keyName) }
        tracker.onRelease = { keyName, _ in releasedKeys.append(keyName) }

        let touch1 = MockTouch(id: 1)
        let touch2 = MockTouch(id: 2)
        let cmdReg = KeyRegistration(keyId: "cmd", keyName: "Cmd", keyType: .modifier, frame: .zero)
        let tabReg = KeyRegistration(keyId: "tab", keyName: "Tab", keyType: .regular, frame: .zero)

        tracker.touchBegan(touch1, key: cmdReg)
        tracker.touchBegan(touch2, key: tabReg)

        XCTAssertEqual(tracker.activeTouchCount, 2)
        XCTAssertEqual(pressedKeys, ["Cmd", "Tab"])

        // Release Tab while Cmd still held
        tracker.touchEnded(touch2)
        XCTAssertEqual(tracker.activeTouchCount, 1)
        XCTAssertEqual(releasedKeys, ["Tab"])

        // Release Cmd
        tracker.touchEnded(touch1)
        XCTAssertEqual(tracker.activeTouchCount, 0)
        XCTAssertEqual(releasedKeys, ["Tab", "Cmd"])
    }

    func testTouchMovedFiresMoved() {
        let tracker = TouchTracker<MockTouch>()
        var movedPoints: [CGPoint] = []
        tracker.onMoved = { point, _ in movedPoints.append(point) }

        let touch = MockTouch(id: 1)
        let reg = KeyRegistration(keyId: "cmd", keyName: "Cmd", keyType: .modifier, frame: .zero)
        tracker.touchBegan(touch, key: reg)
        tracker.touchMoved(touch, point: CGPoint(x: 10, y: 20))

        XCTAssertEqual(movedPoints.count, 1)
        XCTAssertEqual(movedPoints[0], CGPoint(x: 10, y: 20))
    }

    func testCancelAllTouches() {
        let tracker = TouchTracker<MockTouch>()
        var releasedKeys: [String] = []
        tracker.onRelease = { keyName, _ in releasedKeys.append(keyName) }

        let touch1 = MockTouch(id: 1)
        let touch2 = MockTouch(id: 2)
        let cmdReg = KeyRegistration(keyId: "cmd", keyName: "Cmd", keyType: .modifier, frame: .zero)
        let tabReg = KeyRegistration(keyId: "tab", keyName: "Tab", keyType: .regular, frame: .zero)

        tracker.touchBegan(touch1, key: cmdReg)
        tracker.touchBegan(touch2, key: tabReg)
        tracker.cancelAll()

        XCTAssertEqual(tracker.activeTouchCount, 0)
        XCTAssertEqual(Set(releasedKeys), ["Cmd", "Tab"])
    }

    func testEndingUnknownTouchDoesNothing() {
        let tracker = TouchTracker<MockTouch>()
        var releasedKeys: [String] = []
        tracker.onRelease = { keyName, _ in releasedKeys.append(keyName) }

        let unknownTouch = MockTouch(id: 999)
        tracker.touchEnded(unknownTouch)

        XCTAssertEqual(tracker.activeTouchCount, 0)
        XCTAssertTrue(releasedKeys.isEmpty)
    }
}

// MARK: - Mock Touch for testing

/// Lightweight stand-in for UITouch in unit tests.
/// Uses an integer ID for identity comparison (matching UITouch behavior).
final class MockTouch: Hashable {
    let id: Int
    init(id: Int) { self.id = id }

    static func == (lhs: MockTouch, rhs: MockTouch) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
