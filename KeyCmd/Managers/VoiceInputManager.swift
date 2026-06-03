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
    @Published var autoPauseOnSilence: Bool {
        didSet { UserDefaults.standard.set(autoPauseOnSilence, forKey: "VoiceInput.autoPauseOnSilence") }
    }

    private var engine: SpeechRecognitionEngine
    private let logger = LogManager.shared
    private let aiSettings = AISettings.shared

    init(engine: SpeechRecognitionEngine? = nil) {
        // Initialize autoPauseOnSilence from UserDefaults (default: true)
        self.autoPauseOnSilence = UserDefaults.standard.object(forKey: "VoiceInput.autoPauseOnSilence") as? Bool ?? true

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
        
        // Listen for silence detection from engine
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSilenceDetected),
            name: NSNotification.Name("SpeechEngineSilenceDetected"),
            object: nil
        )
    }
    
    @objc private func updatePermissionStatus() {
        DispatchQueue.main.async {
            self.permissionGranted = self.engine.permissionGranted
        }
    }

    @objc private func handleSilenceDetected() {
        logger.log("[SilenceDetect] Notification received: autoPause=\(autoPauseOnSilence), isListening=\(isListening)", category: "VoiceInput")
        guard autoPauseOnSilence && isListening else {
            logger.log("[SilenceDetect] Ignoring: autoPause=\(autoPauseOnSilence), isListening=\(isListening)", category: "VoiceInput")
            return
        }
        DispatchQueue.main.async {
            self.logger.log("[SilenceDetect] Auto-pausing now", category: "VoiceInput")
            self.stopListening()
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
        // For Whisper: mark processing BEFORE setting isListening=false so that
        // observers see isProcessingAudio=true when the isListening change fires.
        if aiSettings.sttEngine == .whisper {
            isProcessingAudio = true
        }
        engine.stopListening()
        isListening = false
        // isProcessingAudio stays true until .final arrives (Whisper may still be running)
        logger.log("Voice input stopped, isProcessingAudio=\(isProcessingAudio)", category: "VoiceInput")
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
