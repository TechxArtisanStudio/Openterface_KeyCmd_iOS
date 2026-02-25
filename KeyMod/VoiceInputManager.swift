//
//  VoiceInputManager.swift
//  KeyMod
//
//  Created on 2026/2/25.
//

import Foundation
import Speech
import AVFoundation

class VoiceInputManager: ObservableObject {
    @Published var transcribedText: String = ""
    @Published var isListening: Bool = false
    @Published var errorMessage: String? = nil
    @Published var permissionGranted: Bool = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let logger = LogManager.shared

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        checkPermissions()
    }

    // MARK: - Permissions

    func checkPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self?.requestMicrophonePermission()
                case .denied, .restricted:
                    self?.permissionGranted = false
                    self?.errorMessage = "Speech recognition permission denied. Please enable it in Settings."
                case .notDetermined:
                    self?.permissionGranted = false
                @unknown default:
                    self?.permissionGranted = false
                }
            }
        }
    }

    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.permissionGranted = granted
                if !granted {
                    self?.errorMessage = "Microphone permission denied. Please enable it in Settings."
                } else {
                    self?.errorMessage = nil
                }
            }
        }
    }

    // MARK: - Recording Control

    func startListening() {
        guard permissionGranted else {
            checkPermissions()
            return
        }
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer is not available."
            return
        }
        guard !audioEngine.isRunning else { return }

        do {
            try startRecognitionSession(speechRecognizer: speechRecognizer)
            isListening = true
            errorMessage = nil
            logger.log("Voice input started", category: "VoiceInput")
        } catch {
            errorMessage = "Could not start voice input: \(error.localizedDescription)"
            logger.log("Voice input start error: \(error)", category: "VoiceInput")
        }
    }

    func stopListening() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
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

    // MARK: - Private

    private func startRecognitionSession(speechRecognizer: SFSpeechRecognizer) throws {
        // Cancel any in-progress task
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "VoiceInputManager", code: -1,
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
                    // Append newly recognized text instead of replacing when session continues
                    self.transcribedText = recognized
                }
            }

            if let error = error {
                let nsError = error as NSError
                // Code 1110 = "No speech detected" — not a real error, just silence
                if nsError.code != 1110 {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                    }
                }
                self.stopListening()
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }
}
