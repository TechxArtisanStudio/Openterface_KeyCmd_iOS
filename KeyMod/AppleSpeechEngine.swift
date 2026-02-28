//
//  AppleSpeechEngine.swift
//  KeyMod
//
//  Created on 2026/2/27.
//

import Foundation
import Speech
import AVFoundation

class AppleSpeechEngine: NSObject, SpeechRecognitionEngine {
    private(set) var isListening: Bool = false
    private(set) var permissionGranted: Bool = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let logger = LogManager.shared
    
    private var onResult: ((SpeechRecognitionResult) -> Void)?
    private var onError: ((Error) -> Void)?

    override init() {
        super.init()
        let localeId = AISettings.shared.sttLocale
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
        checkPermissions()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLocaleChanged),
            name: NSNotification.Name("STTLocaleChanged"),
            object: nil
        )
    }

    @objc private func handleLocaleChanged() {
        let localeId = AISettings.shared.sttLocale
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
        logger.log("Apple speech engine: locale updated to \(localeId)", category: "VoiceInput")
    }

    // MARK: - SpeechRecognitionEngine Protocol

    func startListening(onResult: @escaping (SpeechRecognitionResult) -> Void, onError: @escaping (Error) -> Void) {
        guard permissionGranted else {
            checkPermissions()
            return
        }
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            let error = NSError(domain: "AppleSpeechEngine", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available."])
            onError(error)
            return
        }
        guard !audioEngine.isRunning else { return }

        self.onResult = onResult
        self.onError = onError

        do {
            try startRecognitionSession(speechRecognizer: speechRecognizer)
            isListening = true
            logger.log("Apple speech engine started", category: "VoiceInput")
        } catch {
            isListening = false
            onError(error)
            logger.log("Apple speech engine error: \(error)", category: "VoiceInput")
        }
    }

    func stopListening() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
        logger.log("Apple speech engine stopped", category: "VoiceInput")
    }

    func checkPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.requestMicrophonePermission()
                case .denied, .restricted:
                    self?.permissionGranted = false
                    NotificationCenter.default.post(name: NSNotification.Name("SpeechEnginePermissionChanged"), object: nil)
                case .notDetermined:
                    self?.permissionGranted = false
                    NotificationCenter.default.post(name: NSNotification.Name("SpeechEnginePermissionChanged"), object: nil)
                @unknown default:
                    self?.permissionGranted = false
                    NotificationCenter.default.post(name: NSNotification.Name("SpeechEnginePermissionChanged"), object: nil)
                }
            }
        }
    }

    // MARK: - Private

    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.permissionGranted = granted
                NotificationCenter.default.post(name: NSNotification.Name("SpeechEnginePermissionChanged"), object: nil)
            }
        }
    }

    private func startRecognitionSession(speechRecognizer: SFSpeechRecognizer) throws {
        // Cancel any in-progress task
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "AppleSpeechEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request."])
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let recognized = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    if result.isFinal {
                        self.onResult?(.final(recognized))
                    } else {
                        self.onResult?(.partial(recognized))
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError
                // Code 1110 = "No speech detected" — not a real error
                if nsError.code != 1110 {
                    DispatchQueue.main.async {
                        self.onError?(error)
                    }
                }
                self.stopListening()
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }
}
