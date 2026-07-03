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

    // True when the camera bump/Dynamic Island is on the RIGHT side of the screen
    // (device rotated so its top edge points to the right — UIDeviceOrientation.landscapeRight).
    // Used by keyboard view to shift the keyboard away from the camera.
    @Published var cameraOnRight: Bool = false

    // Store the physical orientation before forcing portrait, so we can restore it
    @Published var savedDeviceOrientation: UIDeviceOrientation?

    // Alternative approach: Show user instruction when programmatic change fails
    @Published var showOrientationInstruction = false
    @Published var instructionText = ""
    
    init() {
        // Enable device orientation notifications so UIDevice.current.orientation is accurate
        // and orientationDidChange fires when the user rotates the device.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

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
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    @objc private func orientationDidChange() {
        DispatchQueue.main.async {
            self.updateOrientation()
        }
    }
    
    func updateOrientation() {
        // Respect the orientation lock when landscape is forced (e.g., keyboard submode).
        // Even if the device is physically in portrait, keep isLandscape = true.
        if preferredOrientation == .landscape {
            // Detect camera side from physical device orientation.
            // The camera module sits at the top of the phone's back. In landscape,
            // "top" maps to one side of the screen — use that to pad the keyboard.
            let deviceOrientation = UIDevice.current.orientation
            DispatchQueue.main.async {
                self.isLandscape = true
                self.cameraOnRight = (deviceOrientation == .landscapeRight)
            }
            return
        }

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let interfaceOrientation = windowScene.interfaceOrientation
            if interfaceOrientation != .unknown {
                isLandscape = interfaceOrientation.isLandscape
                // Interface orientation and camera side are inverse:
                // landscapeLeft = rotated clockwise = camera on RIGHT
                // landscapeRight = rotated counter-clockwise = camera on LEFT
                if interfaceOrientation == .landscapeLeft {
                    cameraOnRight = true
                } else if interfaceOrientation == .landscapeRight {
                    cameraOnRight = false
                }
                return
            }
        }

        let orientation = UIDevice.current.orientation
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            isLandscape = true
            cameraOnRight = (orientation == .landscapeRight)
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
        // ponytail: delay to let the orientation lock propagate
        if #available(iOS 16.0, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: self.preferredOrientation)) { error in
                        print("Geometry update result: \(error.localizedDescription)")
                    }
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
        // Clear any stale saved orientation from a previous portrait lock
        // (e.g. coming from Presentation, Compose, or Numpad).
        savedDeviceOrientation = nil

        preferredOrientation = .landscape
        // Set isLandscape immediately so the keyboard renders in landscape on the
        // very first frame — even if the device is physically held in portrait.
        // This is safe because updateOrientation() now respects preferredOrientation == .landscape.
        isLandscape = true
        Self.setOrientationLock(.landscape)
        UIViewController.attemptRotationToDeviceOrientation()
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                    print("Landscape geometry update rejected: \(error.localizedDescription)")
                }
            }
        }

        // Force a second rotation attempt after a short delay — the system may need
        // time to process the orientation unlock before accepting the landscape lock.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Enable device orientation notifications to detect camera side
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()

            // Update cameraOnRight based on current device orientation
            self.updateCameraSide()

            Self.setOrientationLock(.landscape)
            UIViewController.attemptRotationToDeviceOrientation()
            self.updateOrientation()
        }
    }

    /// Detect which side the camera/Dynamic Island is on based on physical device orientation.
    /// UIDeviceOrientation.landscapeLeft = top of device on left → camera on LEFT.
    /// UIDeviceOrientation.landscapeRight = top of device on right → camera on RIGHT.
    func updateCameraSide() {
        let deviceOrientation = UIDevice.current.orientation
        DispatchQueue.main.async {
            self.cameraOnRight = (deviceOrientation == .landscapeRight)
        }
    }

    func lockToPortrait() {
        // Save current physical orientation so we can restore it later
        savedDeviceOrientation = UIDevice.current.orientation
        preferredOrientation = .portrait
        Self.setOrientationLock(.portrait)
        UIViewController.attemptRotationToDeviceOrientation()

        // ponytail: delay geometry update to let the orientation lock propagate
        // (BSActionErrorDomain error 1 occurs when update is called too quickly)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if #available(iOS 16.0, *) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                        print("Portrait geometry update rejected: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func restoreOrientation() {
        // Clear any stale saved orientation first
        guard let saved = savedDeviceOrientation else {
            // No saved orientation — check what the interface currently is.
            // If we're in portrait (likely from a compose/numpad transition),
            // try to restore to the physical device's natural orientation.
            if #available(iOS 16.0, *), let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let currentOrientation = windowScene.interfaceOrientation
                // Only force rotation if we're currently locked in portrait
                if currentOrientation == .portrait {
                    Self.setOrientationLock(.all)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        UIViewController.attemptRotationToDeviceOrientation()
                    }
                }
            }
            return
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
        // Also force rotation attempt — without this the UI stays in whatever
        // orientation it was locked to (e.g. landscape from gamepad) even though
        // the device may be held differently.
        UIViewController.attemptRotationToDeviceOrientation()
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all)) { _ in }
            }
        }
        // Clear stale saved orientation
        savedDeviceOrientation = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.updateOrientation()
            self.forceUIRefresh()
        }
    }

    /// Set to true while the launch panel is visible to prevent any view
    /// from overriding the portrait lock we apply for that screen.
    static var launchPanelVisible = false

    static func setOrientationLock(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
    }
}
