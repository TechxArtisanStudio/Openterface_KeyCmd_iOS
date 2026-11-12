// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: Copyright (C) 2025-2026 Openterface KeyCmd contributors
// See LICENSE for the full license text.

import XCTest
@testable import KeyCmd

final class PairingPINStoreTests: XCTestCase {

    private let deviceID = UUID()

    override func tearDown() {
        PairingPINStore.delete(for: deviceID)
        super.tearDown()
    }

    func testSaveLoadUpdateAndDelete() {
        XCTAssertNil(PairingPINStore.load(for: deviceID))

        PairingPINStore.save("123456", for: deviceID)
        XCTAssertEqual(PairingPINStore.load(for: deviceID), "123456")

        PairingPINStore.save("654321", for: deviceID)
        XCTAssertEqual(PairingPINStore.load(for: deviceID), "654321")

        PairingPINStore.delete(for: deviceID)
        XCTAssertNil(PairingPINStore.load(for: deviceID))
    }

    func testPINsAreScopedPerDevice() {
        let otherID = UUID()
        defer { PairingPINStore.delete(for: otherID) }

        PairingPINStore.save("111111", for: deviceID)
        PairingPINStore.save("222222", for: otherID)

        XCTAssertEqual(PairingPINStore.load(for: deviceID), "111111")
        XCTAssertEqual(PairingPINStore.load(for: otherID), "222222")
    }
}
