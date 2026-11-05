import XCTest
import SwiftUI
import UIKit
@testable import KeyCmd

final class RenderedKeyboardFrameTests: XCTestCase {

    private var window: UIWindow!
    private var originalLocale: KeyboardLocale!
    private var originalTargetOS: TargetOS!

    override func setUp() {
        super.setUp()

        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        KeyboardLayoutLoader.layoutsDirectoryOverride = "\(projectRoot)/Resources/KeyboardLayouts"

        originalLocale = KeyboardLayoutManager.shared.currentKeyboardLocale
        originalTargetOS = AISettings.shared.targetOS
        KeyboardLayoutManager.shared.clearCache()
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        KeyboardLayoutManager.shared.currentKeyboardLocale = originalLocale
        AISettings.shared.targetOS = originalTargetOS
        KeyboardLayoutLoader.layoutsDirectoryOverride = nil
        KeyboardLayoutManager.shared.clearCache()
        super.tearDown()
    }

    private struct Rendered {
        let containerBounds: CGRect
        let registrations: [KeyRegistration]
    }

    private func render(
        targetOS: TargetOS,
        locale: KeyboardLocale,
        size: CGSize
    ) -> Rendered {
        AISettings.shared.targetOS = targetOS
        KeyboardLayoutManager.shared.currentKeyboardLocale = locale

        let bleManager = BLEManager()
        let view = BasicKeyboardMouseView(
            mouseManager: MouseManager(bleManager: bleManager),
            keyboardManager: KeyboardManager(bleManager: bleManager),
            orientationManager: OrientationManager(),
            selectedSubmode: .constant(.keyboard)
        )

        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()

        // Let SwiftUI lay out and deliver the measured-frame preferences.
        for _ in 0..<30 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        guard let container = findContainer(in: controller.view) else {
            XCTFail("MultiTouchKeyboardContainerView not found in hierarchy")
            return Rendered(containerBounds: .zero, registrations: [])
        }
        return Rendered(
            containerBounds: container.bounds,
            registrations: container.registry.allKeys
        )
    }

    private func findContainer(in view: UIView) -> MultiTouchKeyboardContainerView? {
        if let container = view as? MultiTouchKeyboardContainerView { return container }
        for subview in view.subviews {
            if let found = findContainer(in: subview) { return found }
        }
        return nil
    }

    /// Every key must be registered exactly once. An "Up" key lives in the layout grid
    /// of most layouts (ZXCV row) while the inverted-T cluster draws it too, which
    /// rendered a duplicate up-arrow key.
    func testEveryKeyIsRegisteredOnce() {
        for targetOS in TargetOS.allCases {
            for locale in [KeyboardLocale.us, .de, .jp] {
                let result = render(targetOS: targetOS, locale: locale, size: Self.landscapeSize)
                let names = result.registrations.map(\.keyName)
                let duplicates = Dictionary(grouping: names, by: { $0 })
                    .filter { $0.value.count > 1 }
                    .keys
                XCTAssertTrue(
                    duplicates.isEmpty,
                    "\(targetOS.rawValue)/\(locale.rawValue) registers duplicate keys: \(duplicates.sorted())"
                )
            }
        }
    }

    /// All four arrows are drawn by the cluster and must be hittable at their own center.
    func testArrowClusterIsCompleteAndHittable() {
        for targetOS in TargetOS.allCases {
            let result = render(targetOS: targetOS, locale: .jp, size: Self.landscapeSize)
            for name in ["Up", "Down", "Left", "Right"] {
                guard let reg = result.registrations.last(where: { $0.keyName == name }) else {
                    XCTFail("\(targetOS.rawValue): \(name) is not registered")
                    continue
                }
                let center = CGPoint(x: reg.frame.midX, y: reg.frame.midY)
                let hit = result.registrations.reversed().first { $0.frame.contains(center) }
                XCTAssertEqual(hit?.keyName, name, "\(targetOS.rawValue): \(name) center hits \(hit?.keyName ?? "nil")")
            }
        }
    }

    /// The bottom row must stay clear of the home-indicator gesture strip; keys flush
    /// with the physical bottom edge had their taps delayed/cancelled by the system.
    func testBottomRowClearsGestureStrip() {
        for targetOS in TargetOS.allCases {
            let result = render(targetOS: targetOS, locale: .jp, size: Self.landscapeSize)
            let limit = result.containerBounds.maxY - BasicKeyboardMouseView.bottomGestureInset
            let bounds = result.containerBounds.insetBy(dx: -0.5, dy: -0.5)
            for reg in result.registrations {
                XCTAssertLessThanOrEqual(
                    reg.frame.maxY, limit + 0.5,
                    "\(targetOS.rawValue): \(reg.keyName) extends into the bottom gesture strip (\(reg.frame))"
                )
                XCTAssertTrue(
                    bounds.contains(reg.frame),
                    "\(targetOS.rawValue): \(reg.keyName) is outside the touch container (\(reg.frame))"
                )
            }
        }
    }

    private static let landscapeSize = CGSize(width: 874, height: 402)
}
