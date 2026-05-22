//
//  KeyModApp.swift
//  KeyMod
//
//  Created by 彭志坚 on 2025/6/19.
//

import SwiftUI
import UIKit

// AppDelegate to handle orientation
public class AppDelegate: NSObject, UIApplicationDelegate {
    // Static so any caller can read/write without needing an instance
    public static var orientationLock: UIInterfaceOrientationMask = .all

    public func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Pre-warm the keyboard prediction XPC connection at launch time
        // (outside of any gesture pipeline) so the first tap on a UITextView
        // doesn't trigger the ~3 s "gesture gate timeout".
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let warmupTV = UITextView()
            warmupTV.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
            warmupTV.alpha = 0
            warmupTV.autocorrectionType = .no
            warmupTV.autocapitalizationType = .none
            warmupTV.spellCheckingType = .no
            warmupTV.smartDashesType = .no
            warmupTV.smartQuotesType = .no
            warmupTV.smartInsertDeleteType = .no
            if #available(iOS 17.0, *) { warmupTV.inlinePredictionType = .no }
            warmupTV.textContentType = .none
            // Dummy inputView so becomeFirstResponder() is instant but
            // still initializes the prediction service.
            warmupTV.inputView = UIView(frame: .zero)
            warmupTV.isEditable = true
            warmupTV.isSelectable = true

            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first else { return }
            window.addSubview(warmupTV)
            _ = warmupTV.becomeFirstResponder()
            // Dispose after 2 s — XPC connection has been established.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                warmupTV.resignFirstResponder()
                warmupTV.removeFromSuperview()
            }
        }
        return true
    }
}

@main
struct KeyModApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var launchPanelManager = LaunchPanelManager()
    @StateObject private var themeManager = ThemeManager.shared
    
    init() {
        // Disable keyboard prediction service XPC calls that cause ~3s
        // "gesture gate timeout" on iPad. UITextView's becomeFirstResponder()
        // makes a synchronous XPC to the keyboard prediction daemon which
        // fails ("Operation not authorized") and blocks the main thread.
        // These prefs must be set BEFORE the first UITextView gets focus.
        UserDefaults.standard.set(false, forKey: "KeyboardPredictionEnabled")
        UserDefaults.standard.set(false, forKey: "KeyboardsEnablePredictiveTextInput")
        UserDefaults.standard.set(0, forKey: "WKDisableCrossProcessPredictions")
        // Disable data detectors that also trigger XPC on focus
        UITextView.appearance().dataDetectorTypes = []

        // No forced orientation on startup - let the app start in current device orientation
        // Orientation will be managed per-view by OrientationManager
        print("🚀 KeyModApp initialized - starting in natural device orientation")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(launchPanelManager: launchPanelManager)
                
                if launchPanelManager.showLaunchPanel {
                    LaunchPanelView(launchPanelManager: launchPanelManager)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .tint(themeManager.accentColor)
            .onAppear {
                if launchPanelManager.showLaunchPanel {
                    applyLaunchPanelOrientation(show: true)
                }
            }
            .onChange(of: launchPanelManager.showLaunchPanel) { isShowing in
                applyLaunchPanelOrientation(show: isShowing)
            }
        }
    }

    private func applyLaunchPanelOrientation(show: Bool) {
        OrientationManager.launchPanelVisible = show
        if show {
            AppDelegate.orientationLock = .portrait
            // Short delay so the window scene is fully initialised before
            // requesting a geometry update (needed on cold launch).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                UIViewController.attemptRotationToDeviceOrientation()
                if #available(iOS 16.0, *) {
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
                    }
                }
            }
        } else {
            AppDelegate.orientationLock = .all
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
