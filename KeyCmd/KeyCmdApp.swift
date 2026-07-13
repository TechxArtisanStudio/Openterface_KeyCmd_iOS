//
//  KeyCmdApp.swift
//  KeyCmd
//
//  Created by 彭志坚 on 2025/6/19.
//

import SwiftUI
import UIKit

// AppDelegate to handle orientation
public class AppDelegate: NSObject, UIApplicationDelegate {
    // Static so any caller can read/write without needing an instance
    // Default to portrait since touchpad is the default submode
    public static var orientationLock: UIInterfaceOrientationMask = .portrait

    public func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("🚀 [AppDelegate.didFinishLaunchingWithOptions] START")
        
        // Pre-warm haptic engine at launch so first press feedback is reliable
        // iOS needs time to initialize the Taptic Engine; warming at launch avoids
        // the first-tap silence that users were reporting.
        DispatchQueue.main.async {
            print("⏱️ [AppDelegate.haptic] Main queue async: Starting HapticFeedbackManager init")
            let startTime = Date()
            _ = HapticFeedbackManager.shared
            print("✅ [AppDelegate.haptic] HapticFeedbackManager initialized in \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s")
            
            // Trigger a test haptic after a short delay to ensure the engine is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("⏱️ [AppDelegate.haptic] testHaptic() scheduled")
                HapticFeedbackManager.shared.testHaptic()
            }
        }

        // Skip keyboard prediction XPC warmup - causes XPC connection invalid errors on startup
        // This functionality is not required for the app's core functionality
        print("⏭️ [AppDelegate.keyboard] Skipping keyboard prediction warmup (XPC disabled)")
        print("🚀 [AppDelegate.didFinishLaunchingWithOptions] END (returning true)")
        return true
    }
}

@main
struct KeyCmdApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var launchPanelManager = LaunchPanelManager()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var languageManager = LanguageManager.shared
    
    init() {
        print("🚀 [KeyCmdApp.init] START")
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
        print("✅ [KeyCmdApp.init] UserDefaults configured")
        print("🚀 [KeyCmdApp.init] Starting in natural device orientation")
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
            .environment(\.locale, languageManager.locale)
            .tint(themeManager.accentColor)
            .preferredColorScheme(
                themeManager.followSystem ? nil :
                    (themeManager.modeOverride == .dark ? .dark : .light)
            )
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
