//
//  VoiceInputManager.swift
//  KeyMod
//
//  Created on 2026/2/25.
//

import Foundation

class VoiceInputManager: ObservableObject {
    @Published var transcribedText: String = ""
    @Published var isListening: Bool = false
    /// True while the engine is asynchronously processing audio (e.g. Whisper inference after recording stops).
    @Published var isProcessingAudio: Bool = false
    @Published var errorMessage: String? = nil
    @Published var permissionGranted: Bool = false

    private var engine: SpeechRecognitionEngine
    private let logger = LogManager.shared
    private let aiSettings = AISettings.shared

    init(engine: SpeechRecognitionEngine? = nil) {
        // Use provided engine or create default based on settings
        if let engine = engine {
            self.engine = engine
        } else {
            let selectedEngine = AISettings.shared.sttEngine
            if selectedEngine == .whisper {
                self.engine = WhisperEngine()
            } else {
                self.engine = AppleSpeechEngine()
            }
        }
        
        self.permissionGranted = self.engine.permissionGranted
        
        // Listen for permission changes from engine
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updatePermissionStatus),
            name: NSNotification.Name("SpeechEnginePermissionChanged"),
            object: nil
        )
    }
    
    @objc private func updatePermissionStatus() {
        DispatchQueue.main.async {
            self.permissionGranted = self.engine.permissionGranted
        }
    }

    // MARK: - Recording Control

    func startListening() {
        guard permissionGranted else {
            engine.checkPermissions()
            return
        }

        engine.startListening(
            onResult: { [weak self] result in
                switch result {
                case .partial(let text):
                    DispatchQueue.main.async {
                        self?.transcribedText = text
                        // Mark as processing when Whisper starts async inference
                        if text == "Transcribing with Whisper..." {
                            self?.isProcessingAudio = true
                        }
                    }
                case .final(let text):
                    DispatchQueue.main.async {
                        self?.transcribedText = text
                        self?.isProcessingAudio = false
                    }
                }
            },
            onError: { [weak self] error in
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                    self?.logger.log("Voice input error: \(error)", category: "VoiceInput")
                }
            }
        )
        
        isListening = true
        errorMessage = nil
        logger.log("Voice input started", category: "VoiceInput")
    }

    func stopListening() {
        engine.stopListening()
        isListening = false
        // isProcessingAudio stays true until .final arrives (Whisper may still be running)
        logger.log("Voice input stopped", category: "VoiceInput")
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func clearText() {
        transcribedText = ""
    }
}
