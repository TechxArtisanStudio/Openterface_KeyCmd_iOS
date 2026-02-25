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
    public var orientationLock: UIInterfaceOrientationMask = .all
    
    public func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return orientationLock
    }
}

@main
struct KeyModApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var launchPanelManager = LaunchPanelManager()
    
    init() {
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
        }
    }
}
