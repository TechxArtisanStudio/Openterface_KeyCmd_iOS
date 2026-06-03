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

    // Silence detection
    private var lastSpeechTime: Date = Date()
    private var hasSpeechBeenDetected: Bool = false
    private var silenceTimer: Timer?
    private static let silenceThreshold: Float = 0.004
    static let silenceTimeoutSeconds: TimeInterval = 2.0

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
        stopSilenceTimer()
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
            self?.monitorAudioLevel(buffer)
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
        startSilenceTimer()
    }

    // MARK: - Silence Detection

    private func monitorAudioLevel(_ buffer: AVAudioPCMBuffer) {
        let rms = calculateRMS(buffer)
        if rms > Self.silenceThreshold {
            if !hasSpeechBeenDetected {
                logger.log("[SilenceDetect-Apple] Speech first detected, RMS=\(rms)", category: "VoiceInput")
            }
            hasSpeechBeenDetected = true
            lastSpeechTime = Date()
        }
    }

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let length = Int(buffer.frameLength)
        guard length > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<length {
            sum += channelData[0][i] * channelData[0][i]
        }
        return sqrt(sum / Float(length))
    }

    private func startSilenceTimer() {
        lastSpeechTime = Date()
        hasSpeechBeenDetected = false
        logger.log("[SilenceDetect-Apple] startSilenceTimer called, threshold=\(Self.silenceThreshold), timeout=\(Self.silenceTimeoutSeconds)s", category: "VoiceInput")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let elapsed = Date().timeIntervalSince(self.lastSpeechTime)
                self.logger.log("[SilenceDetect-Apple] Timer tick: isListening=\(self.isListening), hasSpeech=\(self.hasSpeechBeenDetected), silenceElapsed=\(String(format: "%.1f", elapsed))s", category: "VoiceInput")
                guard self.isListening, self.hasSpeechBeenDetected else { return }
                if elapsed >= Self.silenceTimeoutSeconds {
                    self.logger.log("[SilenceDetect-Apple] Silence timeout reached (\(String(format: "%.1f", elapsed))s), posting notification", category: "VoiceInput")
                    self.stopSilenceTimer()
                    NotificationCenter.default.post(name: NSNotification.Name("SpeechEngineSilenceDetected"), object: nil)
                }
            }
        }
    }

    private func stopSilenceTimer() {
        logger.log("[SilenceDetect-Apple] stopSilenceTimer called", category: "VoiceInput")
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}
