//
//  ClipboardManager.swift
//  KeyMod
//
//  Created to handle clipboard detection and management
//

import SwiftUI
import UIKit

class ClipboardManager: NSObject, ObservableObject {
    @Published var lastClipboardContent: String = ""
    @Published var showClipboardPrompt = false
    @Published var pendingClipboardContent: String = ""
    @Published var isMonitoring = false
    
    private var changeCount: Int = 0
    private var monitoringTimer: Timer?
    private let logger = LogManager.shared
    
    override init() {
        super.init()
        // Initialize with current clipboard content
        updateClipboardContent()
    }
    
    // MARK: - Clipboard Monitoring
    
    /// Start monitoring clipboard changes
    func startMonitoring() {
        // Check if monitoring is enabled in settings
        let defaults = UserDefaults.standard
        let monitoringEnabled = defaults.object(forKey: "clipboardMonitoringEnabled") as? Bool ?? true
        
        guard monitoringEnabled else {
            logger.log("Clipboard monitoring is disabled in settings", category: "Clipboard", level: .warning)
            return
        }
        
        guard !isMonitoring else { return }
        
        isMonitoring = true
        changeCount = UIPasteboard.general.changeCount
        
        // Poll clipboard every 0.5 seconds
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboardChanges()
        }
        
        logger.log("Clipboard monitoring started", category: "Clipboard", level: .success)
    }
    
    /// Stop monitoring clipboard changes
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        logger.log("Clipboard monitoring stopped", category: "Clipboard")
    }
    
    /// Check for clipboard changes
    private func checkClipboardChanges() {
        let currentChangeCount = UIPasteboard.general.changeCount
        
        if currentChangeCount != changeCount {
            changeCount = currentChangeCount
            
            if let newContent = UIPasteboard.general.string {
                if newContent != lastClipboardContent {
                    handleNewClipboardContent(newContent)
                }
            }
        }
    }
    
    /// Handle new clipboard content detected
    private func handleNewClipboardContent(_ content: String) {
        lastClipboardContent = content
        pendingClipboardContent = content
        
        logger.log("New clipboard content detected: \(content.prefix(50))...", category: "Clipboard", level: .info)
        
        // Show prompt to ask user if they want to send to target
        DispatchQueue.main.async {
            self.showClipboardPrompt = true
        }
    }
    
    /// Update clipboard content from system clipboard
    private func updateClipboardContent() {
        if let content = UIPasteboard.general.string {
            lastClipboardContent = content
        }
        changeCount = UIPasteboard.general.changeCount
    }
    
    // MARK: - Actions
    
    /// Send clipboard content to target
    func sendClipboardToTarget(_ keyboardManager: KeyboardManager) {
        // Use UnicodeManager so both ASCII and non-ASCII chars are handled correctly
        UnicodeManager.shared.sendText(pendingClipboardContent, keyboardManager: keyboardManager)
        logger.log("Sending clipboard content to target: \(pendingClipboardContent.prefix(50))...", category: "Clipboard")
        // Close the prompt
        showClipboardPrompt = false
        pendingClipboardContent = ""
    }
    
    /// Dismiss the clipboard prompt without sending
    func dismissClipboardPrompt() {
        showClipboardPrompt = false
        pendingClipboardContent = ""
        logger.log("Clipboard prompt dismissed", category: "Clipboard")
    }
    
    /// Manually set clipboard content
    func setClipboardContent(_ content: String) {
        UIPasteboard.general.string = content
        lastClipboardContent = content
        updateClipboardContent()
        logger.log("Clipboard content set to: \(content.prefix(50))...", category: "Clipboard")
    }
    
    /// Get current clipboard content
    func getClipboardContent() -> String {
        return UIPasteboard.general.string ?? ""
    }
    
    /// Clear clipboard
    func clearClipboard() {
        UIPasteboard.general.string = ""
        lastClipboardContent = ""
        updateClipboardContent()
        logger.log("Clipboard cleared", category: "Clipboard")
    }
    
    deinit {
        stopMonitoring()
    }
}
