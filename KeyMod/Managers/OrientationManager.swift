//
//  OrientationManager.swift
//  KeyMod
//
//  Created by AI on 2025/6/21.
//

import SwiftUI
import UIKit

class OrientationManager: ObservableObject {
    @Published var isLandscape: Bool = true
    @Published var preferredOrientation: UIInterfaceOrientationMask = .landscape

    // Store the physical orientation before forcing portrait, so we can restore it
    @Published var savedDeviceOrientation: UIDeviceOrientation?

    // Alternative approach: Show user instruction when programmatic change fails
    @Published var showOrientationInstruction = false
    @Published var instructionText = ""
    
    init() {
        // Check initial orientation
        updateOrientation()
        
        // Listen for orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func orientationDidChange() {
        DispatchQueue.main.async {
            self.updateOrientation()
        }
    }
    
    func updateOrientation() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let interfaceOrientation = windowScene.interfaceOrientation
            if interfaceOrientation != .unknown {
                isLandscape = interfaceOrientation.isLandscape
                return
            }
        }

        let orientation = UIDevice.current.orientation
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            isLandscape = true
        case .portrait, .portraitUpsideDown:
            isLandscape = false
        default:
            // Keep the existing state when the device orientation is ambiguous.
            break
        }
    }
    
    func toggleOrientation() {
        print("=== BEFORE TOGGLE ===")
        printCurrentState()
        
        let newIsLandscape = !isLandscape
        let targetOrientation: UIInterfaceOrientation = newIsLandscape ? .landscapeLeft : .portrait
        
        print("Attempting to change orientation to: \(newIsLandscape ? "Landscape" : "Portrait")")
        
        // Update the preferred orientation
        preferredOrientation = newIsLandscape ? .landscape : .portrait
        
        // Update AppDelegate orientation lock if available
        AppDelegate.orientationLock = preferredOrientation
        print("Updated AppDelegate orientation lock to: \(preferredOrientation)")
        
        // Force rotation attempt if the system allows it.
        UIViewController.attemptRotationToDeviceOrientation()
        print("Attempted rotation to device orientation")

        // Use window scene geometry update on iOS 16+ if available.
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: preferredOrientation)) { error in
                    print("Geometry update result: \(error.localizedDescription)")
                }
            }
        }

        // Method 4: Post notification to trigger UI update
        NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)
        print("Posted orientation change notification")
        
        // Update our published state to trigger UI refresh
        DispatchQueue.main.async {
            self.isLandscape = newIsLandscape
            self.forceUIRefresh()
            print("Updated published state to: \(newIsLandscape ? "Landscape" : "Portrait")")
        }
        
        // Also update after a delay to catch system changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("=== AFTER TOGGLE (0.5s delay) ===")
            self.printCurrentState()
            self.updateOrientation()
        }
    }
    
    // Debugging methods
    func printCurrentState() {
        let deviceOrientation = UIDevice.current.orientation
        print("=== Orientation Debug ===")
        print("Published isLandscape: \(isLandscape)")
        print("Device orientation: \(deviceOrientation)")
        print("Preferred orientation mask: \(preferredOrientation)")
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            print("Interface orientation: \(windowScene.interfaceOrientation)")
        }
        
        // Try to get AppDelegate info safely
        if let appDelegate = UIApplication.shared.delegate {
            print("AppDelegate exists: \(type(of: appDelegate))")
        }
        print("========================")
    }
    
    // Force UI refresh
    func forceUIRefresh() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func toggleOrientationWithInstruction() {
        let newIsLandscape = !isLandscape
        let _: UIInterfaceOrientation = newIsLandscape ? .landscapeLeft : .portrait
        
        print("=== BEFORE TOGGLE ===")
        printCurrentState()
        
        // Try programmatic change first
        toggleOrientation()
        
        // After a delay, check if the change was successful
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let currentOrientation = UIDevice.current.orientation
            let didChangeSuccessfully = (newIsLandscape && currentOrientation.isLandscape) || 
                                      (!newIsLandscape && (currentOrientation == .portrait || currentOrientation == .portraitUpsideDown))
            
            if !didChangeSuccessfully {
                // Show instruction to user
                self.instructionText = newIsLandscape ? 
                    "Please rotate your device to landscape orientation manually" :
                    "Please rotate your device to portrait orientation manually"
                self.showOrientationInstruction = true
                
                // Hide instruction after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.showOrientationInstruction = false
                }
            }
        }
    }
    
    func lockToLandscape() {
        preferredOrientation = .landscape
        Self.setOrientationLock(.landscape)
        UIViewController.attemptRotationToDeviceOrientation()
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                    print("Landscape geometry update rejected: \(error.localizedDescription)")
                }
            }
        }
        // isLandscape will be updated naturally by updateOrientation() when the
        // system completes the rotation. Setting it here creates a race condition:
        // the geometry update is async, but updateOrientation() may read the still-
        // portrait interface and flip isLandscape back to false, triggering feedback.
    }

    func lockToPortrait() {
        // Save current physical orientation so we can restore it later
        savedDeviceOrientation = UIDevice.current.orientation
        preferredOrientation = .portrait
        Self.setOrientationLock(.portrait)
        UIViewController.attemptRotationToDeviceOrientation()
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                    print("Portrait geometry update rejected: \(error.localizedDescription)")
                }
            }
        }
    }

    func restoreOrientation() {
        guard let saved = savedDeviceOrientation else {
            Self.setOrientationLock(.all)
            return
        }
        // Determine the target interface orientation
        let target: UIInterfaceOrientation
        if saved.isLandscape {
            target = .landscapeLeft
        } else {
            target = .portrait
        }
        Self.setOrientationLock(.all)
        UIViewController.attemptRotationToDeviceOrientation()
        if #available(iOS 16.0, *) {
            let mask: UIInterfaceOrientationMask = saved.isLandscape ? .landscape : .portrait
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                    print("Restore geometry update rejected: \(error.localizedDescription)")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.updateOrientation()
            self.forceUIRefresh()
        }
    }

    func unlockOrientation() {
        Self.setOrientationLock(.all)
    }

    /// Set to true while the launch panel is visible to prevent any view
    /// from overriding the portrait lock we apply for that screen.
    static var launchPanelVisible = false

    static func setOrientationLock(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
    }
}
