//
//  WhisperEngine.swift
//  KeyMod
//
//  Created on 2026/2/27.
//

import Foundation
import AVFoundation

class WhisperEngine: NSObject, SpeechRecognitionEngine {
    private(set) var isListening: Bool = false
    private(set) var permissionGranted: Bool = false

    private let audioEngine = AVAudioEngine()
    private let logger = LogManager.shared
    
    private var onResult: ((SpeechRecognitionResult) -> Void)?
    private var onError: ((Error) -> Void)?
    private var audioBuffer: AVAudioPCMBuffer?
    // Store copies of incoming buffers so we can safely write them after capture stops
    private var capturedBuffers: [AVAudioPCMBuffer] = []
    // Serial queue to protect capturedBuffers (tap runs on real-time audio thread)
    private let bufferQueue = DispatchQueue(label: "KeyMod.WhisperEngine.bufferQueue")
    private let modelManager: WhisperModelManager

    // Silence detection
    private var lastSpeechTime: Date = Date()
    private var hasSpeechBeenDetected: Bool = false
    private var silenceTimer: Timer?
    private var rmsLogCounter: Int = 0
    private static let silenceThreshold: Float = 0.004
    static let silenceTimeoutSeconds: TimeInterval = 2.0
    
    init(modelManager: WhisperModelManager = WhisperModelManager.shared) {
        self.modelManager = modelManager
        super.init()
        checkPermissions()
    }

    // MARK: - SpeechRecognitionEngine Protocol

    func startListening(onResult: @escaping (SpeechRecognitionResult) -> Void, onError: @escaping (Error) -> Void) {
        guard permissionGranted else {
            checkPermissions()
            return
        }

        self.onResult = onResult
        self.onError = onError

        do {
            try setupAudioSession()
            try startAudioCapture()
            isListening = true
            logger.log("Whisper engine started", category: "VoiceInput")
        } catch {
            isListening = false
            onError(error)
            logger.log("Whisper engine error: \(error)", category: "VoiceInput")
        }
    }

    func stopListening() {
        guard audioEngine.isRunning else { return }
        
        stopSilenceTimer()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
        
        // Process captured audio through Whisper (write all captured buffers)
        var buffers: [AVAudioPCMBuffer] = []
        bufferQueue.sync {
            buffers = self.capturedBuffers
            self.capturedBuffers.removeAll()
        }
        logger.log("stopListening: capturedBuffers.count=\(buffers.count)", category: "VoiceInput")
        if !buffers.isEmpty {
            transcribeAudio(buffers)
        } else {
            // No audio captured — send empty final so isProcessingAudio gets cleared
            DispatchQueue.main.async {
                self.onResult?(.final(""))
            }
        }
        
        logger.log("Whisper engine stopped", category: "VoiceInput")
    }

    func checkPermissions() {
        // Request microphone permission
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.permissionGranted = granted
                NotificationCenter.default.post(name: NSNotification.Name("SpeechEnginePermissionChanged"), object: nil)
            }
        }
    }

    // MARK: - Private

    private func setupAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startAudioCapture() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // recordingFormat is guaranteed to be non-nil for input node
        // We'll capture incoming buffers by copying them; the tap-provided buffer is transient
        capturedBuffers = []

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.monitorAudioLevel(buffer)
            if let copy = self.copyPCMBuffer(buffer) {
                // Append on serial queue to avoid concurrent mutation from audio thread
                self.bufferQueue.async {
                    self.capturedBuffers.append(copy)
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        startSilenceTimer()
    }

    private func transcribeAudio(_ audioBuffer: AVAudioPCMBuffer) {
        // Export audio buffer to WAV and ask model manager to transcribe the file.
        // This keeps inference pluggable: when `whisper.cpp` bindings are available,
        // implement the actual inference inside `WhisperModelManager.transcribeAudioFile(_:)`.

        Task {
            // Check if model is downloaded
            guard modelManager.isDownloaded else {
                let error = NSError(domain: "WhisperEngine", code: -2,
                                   userInfo: [NSLocalizedDescriptionKey: "Whisper model not downloaded. Please download in settings."])
                DispatchQueue.main.async {
                    self.onError?(error)
                }
                return
            }

            // Create a temporary file URL for WAV export
                let tempDir = FileManager.default.temporaryDirectory
                let filename = "whisper_input_\(UUID().uuidString).wav"
                let fileURL = tempDir.appendingPathComponent(filename)
                logger.log("transcribeAudio(single): preparing export to \(fileURL.path), frames=\(audioBuffer.frameLength), format=\(audioBuffer.format) ", category: "VoiceInput")

            do {
                try await exportBufferToWav(audioBuffer, fileURL: fileURL)

                    DispatchQueue.main.async {
                        self.onResult?(.partial("Transcribing with Whisper..."))
                    }

                // Ask the model manager to transcribe the file. This is async and pluggable.
                let language = AISettings.shared.currentSTTLanguage.whisperCode
                let transcription = try await modelManager.transcribeAudioFile(fileURL, language: language)
                let finalText = normalizeChineseScript(transcription)

                DispatchQueue.main.async {
                    self.onResult?(.final(finalText))
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: fileURL)
                } catch {
                    logger.log("transcribeAudio(single) error: \(error)", category: "VoiceInput")
                    DispatchQueue.main.async {
                        self.onError?(error)
                    }
                }
            }
        }

    // Transcribe an array of captured buffers — resample in memory, no WAV file.
    private func transcribeAudio(_ buffers: [AVAudioPCMBuffer]) {
        logger.log("transcribeAudio(buffers): count=\(buffers.count)", category: "VoiceInput")
        Task {
            guard modelManager.isDownloaded else {
                let error = NSError(domain: "WhisperEngine", code: -2,
                                   userInfo: [NSLocalizedDescriptionKey: "Whisper model not downloaded. Please download in settings."])
                logger.log("transcribeAudio(buffers) aborted: model not downloaded", category: "VoiceInput")
                DispatchQueue.main.async { self.onError?(error) }
                return
            }

            DispatchQueue.main.async {
                self.onResult?(.partial("Transcribing with Whisper..."))
            }

            do {
                let samples = try resampleBuffersTo16kHz(buffers)
                logger.log("transcribeAudio(buffers): resampled to \(samples.count) samples @ 16kHz", category: "VoiceInput")
                let language = AISettings.shared.currentSTTLanguage.whisperCode
                let transcription = try await modelManager.transcribeAudioSamples(samples, language: language)
                let finalText = normalizeChineseScript(transcription)
                DispatchQueue.main.async { self.onResult?(.final(finalText)) }
            } catch {
                logger.log("transcribeAudio(buffers) error: \(error)", category: "VoiceInput")
                DispatchQueue.main.async { self.onError?(error) }
            }
        }
    }

    /// Merges and resamples an array of AVAudioPCMBuffers to 16 kHz mono Float32 in memory.
    private func resampleBuffersTo16kHz(_ buffers: [AVAudioPCMBuffer]) throws -> [Float] {
        guard let first = buffers.first else { return [] }
        let srcFormat = first.format

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "WhisperEngine", code: -6,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create 16kHz target format"])
        }

        // Step 1: Concatenate all captured Float32 samples into one contiguous buffer.
        // All capture buffers share the same format (same tap), so this is safe.
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard let mergedBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(totalFrames)) else {
            throw NSError(domain: "WhisperEngine", code: -7,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to allocate merged buffer"])
        }
        mergedBuffer.frameLength = AVAudioFrameCount(totalFrames)

        if let dst = mergedBuffer.floatChannelData {
            var offset = 0
            for buf in buffers {
                let frames = Int(buf.frameLength)
                if frames == 0 { continue }
                // Mono: channel 0 only
                if let src = buf.floatChannelData {
                    dst[0].advanced(by: offset).update(from: src[0], count: frames)
                }
                offset += frames
            }
        }

        // Step 2: Single-pass conversion from srcFormat (48kHz Float32) → 16kHz Float32.
        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else {
            throw NSError(domain: "WhisperEngine", code: -8,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }

        let ratio = targetFormat.sampleRate / srcFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(totalFrames) * ratio) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw NSError(domain: "WhisperEngine", code: -9,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output buffer"])
        }

        var provided = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if provided {
                outStatus.pointee = .endOfStream
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return mergedBuffer
        }

        var convError: NSError?
        converter.convert(to: outputBuffer, error: &convError, withInputFrom: inputBlock)
        if let e = convError { throw e }

        guard let channelData = outputBuffer.floatChannelData else {
            throw NSError(domain: "WhisperEngine", code: -10,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to get float channel data"])
        }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }

    private func exportBufferToWav(_ buffer: AVAudioPCMBuffer, fileURL: URL) async throws {
        // Convert buffer to WAV file (16-bit PCM, little endian)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: buffer.format.sampleRate,
                                         channels: buffer.format.channelCount,
                                         interleaved: true) else {
            throw NSError(domain: "WhisperEngine", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"]) 
        }

        // Create an AVAudioFile for writing
        logger.log("exportBufferToWav: writing single buffer frames=\(buffer.frameLength) to \(fileURL.path)", category: "VoiceInput")
        // Log format details before creating file
        logger.log("exportBuffersToWav: target format sampleRate=\(format.sampleRate) channels=\(format.channelCount) commonFormat=\(format.commonFormat) interleaved=\(format.isInterleaved)", category: "VoiceInput")
        logger.log("exportBuffersToWav: fileURL=\(fileURL.path)", category: "VoiceInput")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            logger.log("exportBuffersToWav: file already exists, removing", category: "VoiceInput")
            try? FileManager.default.removeItem(at: fileURL)
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        } catch {
            logger.log("exportBuffersToWav: failed to create AVAudioFile: \(error)", category: "VoiceInput")
            throw error
        }

        // AVAudioPCMBuffer may be in non-interleaved float format. Convert if needed.
        if buffer.format.commonFormat == .pcmFormatFloat32 {
            // Convert to desired format
            guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
                throw NSError(domain: "WhisperEngine", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"]) 
            }

            var _provided = false
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                if _provided {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                _provided = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameCapacity) else {
                throw NSError(domain: "WhisperEngine", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate converted buffer"]) 
            }

            var conversionError: NSError?
            logger.log("exportBufferToWav: converting buffer frames=\(buffer.frameLength)", category: "VoiceInput")
            converter.convert(to: convertedBuffer, error: &conversionError, withInputFrom: inputBlock)
            if let e = conversionError { logger.log("exportBufferToWav conversion error: \(e)", category: "VoiceInput"); throw e }

            try file.write(from: convertedBuffer)
            logger.log("exportBufferToWav: wrote converted buffer frames=\(convertedBuffer.frameLength) to \(fileURL.path)", category: "VoiceInput")
        } else {
            try file.write(from: buffer)
            logger.log("exportBufferToWav: wrote raw buffer frames=\(buffer.frameLength) to \(fileURL.path)", category: "VoiceInput")
        }
        }

    // Exports multiple buffers sequentially into a single WAV file
    private func exportBuffersToWav(_ buffers: [AVAudioPCMBuffer], fileURL: URL) async throws {
        guard let first = buffers.first else { return }

        // Create WAV file with 16-bit PCM settings.
        // AVAudioFile sets processingFormat = Float32 non-interleaved automatically;
        // write(from:) accepts that format and handles the Int16/interleaving conversion internally.
        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: first.format.sampleRate,
            AVNumberOfChannelsKey: first.format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let file = try AVAudioFile(forWriting: fileURL, settings: wavSettings)

        // processingFormat is Float32 non-interleaved — always write in this format
        let procFormat = file.processingFormat

        for (idx, buffer) in buffers.enumerated() {
            logger.log("exportBuffersToWav: buffer[\(idx)] frames=\(buffer.frameLength) format=\(buffer.format)", category: "VoiceInput")

            if buffer.format == procFormat {
                // Already in the right format — write directly
                try file.write(from: buffer)
                logger.log("exportBuffersToWav: wrote raw buffer[\(idx)] frames=\(buffer.frameLength)", category: "VoiceInput")
            } else {
                // Convert to processingFormat before writing
                guard let converter = AVAudioConverter(from: buffer.format, to: procFormat) else {
                    logger.log("exportBuffersToWav: failed to create converter for buffer[\(idx)]", category: "VoiceInput")
                    throw NSError(domain: "WhisperEngine", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
                }

                // Scale frame capacity by sample-rate ratio to avoid under-allocation
                let ratio = procFormat.sampleRate / buffer.format.sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16

                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: procFormat, frameCapacity: capacity) else {
                    logger.log("exportBuffersToWav: failed to allocate convertedBuffer for buffer[\(idx)]", category: "VoiceInput")
                    throw NSError(domain: "WhisperEngine", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate converted buffer"])
                }

                var provided = false
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    guard !provided else {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    provided = true
                    outStatus.pointee = .haveData
                    return buffer
                }

                var convError: NSError?
                let status = converter.convert(to: convertedBuffer, error: &convError, withInputFrom: inputBlock)
                logger.log("exportBuffersToWav: converter status=\(status) buffer[\(idx)] outFrames=\(convertedBuffer.frameLength)", category: "VoiceInput")

                if let e = convError {
                    logger.log("exportBuffersToWav: conversion error for buffer[\(idx)]: \(e)", category: "VoiceInput")
                    throw e
                }

                if convertedBuffer.frameLength > 0 {
                    try file.write(from: convertedBuffer)
                    logger.log("exportBuffersToWav: wrote converted buffer[\(idx)] frames=\(convertedBuffer.frameLength)", category: "VoiceInput")
                }
            }
        }
    }

    /// Converts Traditional Chinese characters to Simplified Chinese when the user's
    /// selected locale is zh-Hans. Whisper.cpp outputs Traditional by default for all
    /// "zh" variants, so we post-process with CFStringTransform("Hant-Hans").
    /// For all other locales the text is returned unchanged.
    private func normalizeChineseScript(_ text: String) -> String {
        guard AISettings.shared.sttLocale == "zh-Hans" else { return text }
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Hant-Hans" as CFString, false)
        return mutable as String
    }

    // Create a deep copy of an AVAudioPCMBuffer
    private func copyPCMBuffer(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: src.frameCapacity) else { return nil }
        copy.frameLength = src.frameLength

        let srcList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: src.audioBufferList))
        let dstList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: copy.audioBufferList))

        let count = min(srcList.count, dstList.count)
        for i in 0..<count {
            let srcBuf = srcList[i]
            var dstBuf = dstList[i]
            if let srcData = srcBuf.mData, let dstData = dstBuf.mData {
                memcpy(dstData, srcData, Int(srcBuf.mDataByteSize))
                dstBuf.mDataByteSize = srcBuf.mDataByteSize
            }
        }

        return copy
    }

    // MARK: - Silence Detection

    private func monitorAudioLevel(_ buffer: AVAudioPCMBuffer) {
        let rms = calculateRMS(buffer)
        rmsLogCounter += 1
        // Log every 10 buffers (~every second) to diagnose
        if rmsLogCounter % 10 == 1 {
            logger.log("[SilenceDetect-Whisper] RMS sample: \(rms), format: \(buffer.format), frames: \(buffer.frameLength), floatChannelData: \(buffer.floatChannelData != nil), channels: \(buffer.format.channelCount), commonFormat: \(buffer.format.commonFormat.rawValue)", category: "VoiceInput")
        }
        if rms > Self.silenceThreshold {
            if !hasSpeechBeenDetected {
                logger.log("[SilenceDetect-Whisper] Speech first detected, RMS=\(rms)", category: "VoiceInput")
            }
            hasSpeechBeenDetected = true
            lastSpeechTime = Date()
        }
    }

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        // Try floatChannelData first (non-interleaved float32)
        if let channelData = buffer.floatChannelData {
            let length = Int(buffer.frameLength)
            guard length > 0 else { return 0 }
            var sum: Float = 0
            for i in 0..<length {
                sum += channelData[0][i] * channelData[0][i]
            }
            return sqrt(sum / Float(length))
        }
        
        // Try int16 data (interleaved)
        if let int16Data = buffer.int16ChannelData {
            let length = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            guard length > 0 else { return 0 }
            var sum: Float = 0
            for i in 0..<length {
                let sample = Float(int16Data[0][i * channels]) / 32768.0
                sum += sample * sample
            }
            return sqrt(sum / Float(length))
        }
        
        // Try int32 data
        if let int32Data = buffer.int32ChannelData {
            let length = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            guard length > 0 else { return 0 }
            var sum: Float = 0
            for i in 0..<length {
                let sample = Float(int32Data[0][i * channels]) / Float(Int32.max)
                sum += sample * sample
            }
            return sqrt(sum / Float(length))
        }
        
        return 0
    }

    private func startSilenceTimer() {
        lastSpeechTime = Date()
        hasSpeechBeenDetected = false
        rmsLogCounter = 0
        logger.log("[SilenceDetect-Whisper] startSilenceTimer called, threshold=\(Self.silenceThreshold), timeout=\(Self.silenceTimeoutSeconds)s", category: "VoiceInput")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let elapsed = Date().timeIntervalSince(self.lastSpeechTime)
                self.logger.log("[SilenceDetect-Whisper] Timer tick: isListening=\(self.isListening), hasSpeech=\(self.hasSpeechBeenDetected), silenceElapsed=\(String(format: "%.1f", elapsed))s", category: "VoiceInput")
                guard self.isListening, self.hasSpeechBeenDetected else { return }
                if elapsed >= Self.silenceTimeoutSeconds {
                    self.logger.log("[SilenceDetect-Whisper] Silence timeout reached (\(String(format: "%.1f", elapsed))s), posting notification", category: "VoiceInput")
                    self.stopSilenceTimer()
                    NotificationCenter.default.post(name: NSNotification.Name("SpeechEngineSilenceDetected"), object: nil)
                }
            }
        }
    }

    private func stopSilenceTimer() {
        logger.log("[SilenceDetect-Whisper] stopSilenceTimer called", category: "VoiceInput")
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}
