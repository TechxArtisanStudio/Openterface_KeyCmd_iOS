//
//  SpeechRecognitionEngine.swift
//  KeyMod
//
//  Created on 2026/2/27.
//

import Foundation

enum SpeechRecognitionResult {
    case partial(String)
    case final(String)
}

protocol SpeechRecognitionEngine: AnyObject {
    /// Start listening for speech input
    func startListening(onResult: @escaping (SpeechRecognitionResult) -> Void, onError: @escaping (Error) -> Void)
    
    /// Stop listening
    func stopListening()
    
    /// Check if currently listening
    var isListening: Bool { get }
    
    /// Check if permissions are granted
    var permissionGranted: Bool { get }
    
    /// Request necessary permissions
    func checkPermissions()
}

enum SpeechEngineType: String, Codable {
    case apple = "apple"
    case whisper = "whisper"
}
