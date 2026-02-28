//
//  WhisperModelManager.swift
//  KeyMod
//
//  Created on 2026/2/27.
//

import Foundation
import AVFoundation
import whisper

class WhisperModelManager: NSObject, ObservableObject {
    @Published var isDownloaded: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var downloadError: String? = nil

    /// The currently active model spec. Changing this frees the cached whisper context
    /// and re-checks whether the new model's file is already present on disk.
    @Published var selectedModel: WhisperModelSpec {
        didSet {
            guard oldValue != selectedModel else { return }
            UserDefaults.standard.set(selectedModel.id, forKey: "WhisperModelManager.selectedModel")
            // Free cached context so the new model is loaded on the next inference call
            whisperQueue.async { [weak self] in
                guard let self else { return }
                if let ctx = self.whisperCtx {
                    whisper_free(ctx)
                    self.whisperCtx = nil
                    self.logger.log("Whisper context freed (model changed to \(self.selectedModel.displayName))", category: "WhisperModel")
                }
            }
            checkIfModelExists()
        }
    }

    static let shared = WhisperModelManager()

    private let logger = LogManager.shared

    // Computed shorthands that always reflect the active model selection
    private var modelFileName:    String { selectedModel.fileName }
    private var modelURLString:   String { selectedModel.downloadURL }
    private var expectedFileSize: Int    { selectedModel.expectedFileSize }

    // Persistent whisper context – loaded once, reused across every transcription call.
    // whisper_full is NOT thread-safe, so all access runs on this serial queue.
    private var whisperCtx: OpaquePointer? = nil
    private let whisperQueue = DispatchQueue(label: "KeyMod.WhisperModelManager.inference", qos: .userInitiated)

    private override init() {
        let savedId = UserDefaults.standard.string(forKey: "WhisperModelManager.selectedModel") ?? "en"
        // Resolve from catalog; fall back to first available model
        self.selectedModel = WhisperModelCatalog.shared.spec(for: savedId)
            ?? WhisperModelCatalog.shared.models.first
            ?? WhisperModelSpec(id: "en",
                                displayName: "Tiny – English Only",
                                fileName: "ggml-tiny.en.bin",
                                downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin",
                                expectedFileSize: 74_000_000,
                                language: "en")
        super.init()
        checkIfModelExists()
    }
    
    // MARK: - Public
    
    var modelPath: URL? {
        let fileURL = getModelFileURL()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }
    
    func downloadModel() async throws {
        logger.log("[DL] downloadModel() called – model: \(selectedModel.id) (\(selectedModel.fileName)), url: \(modelURLString)", category: "WhisperModel")
        DispatchQueue.main.async {
            self.isDownloading = true
            self.downloadError = nil
            self.downloadProgress = 0.0
        }
        
        do {
            // Check available disk space
            logger.log("[DL] Checking disk space…", category: "WhisperModel")
            try checkDiskSpace()

            let fileURL = getModelFileURL()
            logger.log("[DL] Destination file URL: \(fileURL.path)", category: "WhisperModel")

            // Remove existing file if present
            if FileManager.default.fileExists(atPath: fileURL.path) {
                logger.log("[DL] Removing existing file before download", category: "WhisperModel")
                try? FileManager.default.removeItem(at: fileURL)
            }

            // Try downloading with a small retry loop. Sometimes mirrors return HTML or partial content (rate limits).
            var lastError: Error?
            let maxAttempts = 3
            for attempt in 1...maxAttempts {
                logger.log("[DL] Attempt \(attempt)/\(maxAttempts) – starting downloadFile()", category: "WhisperModel")
                do {
                    try await downloadFile(from: modelURLString, to: fileURL)
                    logger.log("[DL] downloadFile() returned successfully on attempt \(attempt) – starting verification", category: "WhisperModel")
                    try verifyDownloadedFile(at: fileURL)
                    logger.log("[DL] Verification passed on attempt \(attempt)", category: "WhisperModel")

                    // Set isDownloaded and isDownloading together in one dispatch so the UI
                    // never sees the intermediate state (isDownloading=false, isDownloaded=false)
                    // that would cause the progress bar to flash back to 0%.
                    DispatchQueue.main.async {
                        self.downloadProgress = 1.0
                        self.isDownloaded = true
                        self.isDownloading = false
                        self.logger.log("[DL] State updated: isDownloaded=true, isDownloading=false, progress=1.0", category: "WhisperModel")
                    }
                    // Pre-load the context immediately after download so first transcription is instant
                    warmupIfNeeded()
                    lastError = nil
                    break
                } catch {
                    logger.log("[DL] Attempt \(attempt) failed with error: \(error)", category: "WhisperModel")
                    lastError = error
                    // Remove possibly-bad file before retrying
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        logger.log("[DL] Removing bad file before retry", category: "WhisperModel")
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    if attempt < maxAttempts {
                        logger.log("[DL] Backing off \(attempt)s before retry…", category: "WhisperModel")
                        try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * UInt64(attempt)))
                    }
                }
            }

            if let error = lastError {
                logger.log("[DL] All \(maxAttempts) attempts exhausted. Final error: \(error)", category: "WhisperModel")
                DispatchQueue.main.async {
                    self.downloadError = error.localizedDescription
                    self.isDownloaded = false
                    self.isDownloading = false
                    self.logger.log("[DL] State updated: isDownloaded=false, isDownloading=false (all retries failed)", category: "WhisperModel")
                }
                throw lastError!
            } else {
                logger.log("[DL] downloadModel() completed successfully", category: "WhisperModel")
            }
        } catch {
            logger.log("[DL] downloadModel() outer catch – error: \(error)", category: "WhisperModel")
            DispatchQueue.main.async {
                self.downloadError = error.localizedDescription
                self.isDownloaded = false
                self.isDownloading = false
                self.logger.log("[DL] State updated: isDownloaded=false, isDownloading=false (outer catch)", category: "WhisperModel")
            }
            throw error
        }
    }
    
    /// Pre-loads the whisper context so the first `transcribeAudioSamples` call incurs no model-load delay.
    /// Safe to call multiple times — loads only if the context is not already initialised.
    func warmupIfNeeded() {
        guard let modelURL = modelPath else { return }
        let path = modelURL.path
        whisperQueue.async { [weak self] in
            guard let self else { return }
            guard self.whisperCtx == nil else { return }
            self.logger.log("Warming up Whisper context (background load)…", category: "WhisperModel")
            self.whisperCtx = whisper_init_from_file(path)
            if self.whisperCtx != nil {
                self.logger.log("Whisper context ready", category: "WhisperModel")
            } else {
                self.logger.log("Whisper context warmup failed", category: "WhisperModel")
            }
        }
    }

    func deleteModel() throws {
        let fileURL = getModelFileURL()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            // Free the cached context so it isn't used with a missing model file
            whisperQueue.sync {
                if let ctx = self.whisperCtx {
                    whisper_free(ctx)
                    self.whisperCtx = nil
                    self.logger.log("Whisper context freed", category: "WhisperModel")
                }
            }
            DispatchQueue.main.async {
                self.isDownloaded = false
                self.downloadProgress = 0.0
                self.logger.log("Whisper model deleted", category: "WhisperModel")
            }
        }
    }
    
    // MARK: - Private
    
    private func checkIfModelExists() {
        let fileURL = getModelFileURL()
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        DispatchQueue.main.async {
            self.isDownloaded = exists
        }
        if exists {
            // Pre-load context in the background so the first transcription is instant
            warmupIfNeeded()
        }
    }
    
    private func getModelFileURL() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDirectory = documentsURL.appendingPathComponent("whisper_models", isDirectory: true)
        return modelsDirectory.appendingPathComponent(modelFileName)
    }
    
    private func checkDiskSpace() throws {
        do {
            let fileAttributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            guard let freeSpace = fileAttributes[FileAttributeKey.systemFreeSize] as? NSNumber else {
                throw NSError(domain: "WhisperModelManager", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Unable to determine available disk space"])
            }
            
            let freeSpaceBytes = freeSpace.int64Value
            let requiredSpace: Int64 = 500_000_000 // ~500MB buffer
            
            guard freeSpaceBytes > requiredSpace else {
                throw NSError(domain: "WhisperModelManager", code: -2,
                             userInfo: [NSLocalizedDescriptionKey: "Not enough disk space. Please free up at least 500MB"])
            }
        } catch {
            throw error
        }
    }
    
    private func downloadFile(from urlString: String, to destination: URL) async throws {
        logger.log("[DL] downloadFile() – url: \(urlString)", category: "WhisperModel")
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "WhisperModelManager", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid model URL"])
        }
        
        // Create models directory if it doesn't exist
        let modelsDirectory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300 // 5 minutes
        configuration.waitsForConnectivity = true
        
        // Use URLSessionDownloadDelegate for progress tracking and bridge to async/await.
        // NOTE: The delegate moves the temp file synchronously inside didFinishDownloadingTo
        // because URLSession deletes the temp file as soon as that delegate method returns.
        let downloadDelegate = DownloadDelegate(
            destination: destination,
            expectedFileSize: expectedFileSize
        ) { [weak self] progress in
            DispatchQueue.main.async {
                self?.downloadProgress = progress
            }
        }

        let delegateSession = URLSession(configuration: configuration, delegate: downloadDelegate, delegateQueue: nil)

        // Start download task and await completion via continuation set by delegate
        let task = delegateSession.downloadTask(with: url)
        logger.log("[DL] URLSession download task created, resuming…", category: "WhisperModel")
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLResponse, Error>) in
            downloadDelegate.continuation = continuation
            task.resume()
        }
        logger.log("[DL] Continuation resumed – file already moved to destination by delegate", category: "WhisperModel")
        
        // Verify HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            logger.log("[DL] HTTP status: \(httpResponse.statusCode), Content-Length header: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "nil")", category: "WhisperModel")
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "WhisperModelManager", code: -4,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response: status \(httpResponse.statusCode)"])
            }
        } else {
            logger.log("[DL] Response is not HTTPURLResponse – type: \(type(of: response))", category: "WhisperModel")
            throw NSError(domain: "WhisperModelManager", code: -4,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response (not HTTPURLResponse)"])
        }
    }
    
    private func verifyDownloadedFile(at url: URL) throws {
        logger.log("[DL] verifyDownloadedFile() – path: \(url.path)", category: "WhisperModel")
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.log("[DL] VERIFY FAIL: file does not exist at path", category: "WhisperModel")
            throw NSError(domain: "WhisperModelManager", code: -5,
                         userInfo: [NSLocalizedDescriptionKey: "Downloaded file not found"])
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[FileAttributeKey.size] as? NSNumber else {
            throw NSError(domain: "WhisperModelManager", code: -6,
                         userInfo: [NSLocalizedDescriptionKey: "Unable to determine file size"])
        }
        
        let actualSize = fileSize.intValue
        logger.log("[DL] Actual file size: \(actualSize) bytes (\(actualSize / 1_000_000) MB) | Expected: \(expectedFileSize) bytes (\(expectedFileSize / 1_000_000) MB)", category: "WhisperModel")

        // Quick sanity check: ensure file is not an HTML error page or clearly truncated
        // Read first bytes to detect HTML/text responses (common when mirrors return an error page)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let headerData = try handle.read(upToCount: 512) ?? Data()
        if let headerString = String(data: headerData, encoding: .utf8)?.lowercased() {
            let isHtml = headerString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!doctype html")
                      || headerString.hasPrefix("<html")
                      || (headerString.contains("error") && headerString.contains("huggingface"))
            logger.log("[DL] File header (first 128 chars): \(String(headerString.prefix(128)))", category: "WhisperModel")
            if isHtml {
                logger.log("[DL] VERIFY FAIL: file is an HTML error page", category: "WhisperModel")
                try FileManager.default.removeItem(at: url)
                throw NSError(domain: "WhisperModelManager", code: -8,
                             userInfo: [NSLocalizedDescriptionKey: "Downloaded file appears to be an HTML error page (likely a mirror or rate-limit response). Please try again later or from a different network."])
            }
        }

        // Allow some tolerance in file size (within 15%) to tolerate small differences or compression
        let tolerance = Int(Double(expectedFileSize) * 0.15)
        let minSize = expectedFileSize - tolerance
        logger.log("[DL] Size check: actualSize=\(actualSize) >= minSize=\(minSize)? \(actualSize >= minSize)", category: "WhisperModel")
        // Accept if file is reasonably large; otherwise treat as truncated
        guard actualSize >= minSize else {
            logger.log("[DL] VERIFY FAIL: file too small (\(actualSize) < \(minSize))", category: "WhisperModel")
            try FileManager.default.removeItem(at: url)
            throw NSError(domain: "WhisperModelManager", code: -7,
                         userInfo: [NSLocalizedDescriptionKey: "Downloaded file size mismatch. Expected ~\(expectedFileSize / 1_000_000)MB, got \(actualSize / 1_000_000)MB. This often indicates a truncated download or a mirror returning HTML (rate limit). Please retry or use a different network."])
        }
        logger.log("[DL] Verification passed – file looks valid", category: "WhisperModel")
    }

    // MARK: - Transcription

    /// Transcribes pre-resampled 16 kHz mono Float32 samples directly (no disk I/O).
    /// Prefer this over `transcribeAudioFile` when samples are already available in memory.
    /// - Parameter language: Optional whisper.cpp language code (e.g. "zh", "ja"). Only applied
    ///   to multilingual models; English-only models always use "en".
    func transcribeAudioSamples(_ samples: [Float], language: String? = nil) async throws -> String {
        guard isDownloaded, let modelURL = modelPath else {
            throw NSError(domain: "WhisperModelManager", code: -9,
                         userInfo: [NSLocalizedDescriptionKey: "Whisper model not downloaded"])
        }
        logger.log("transcribeAudioSamples: \(samples.count) samples", category: "WhisperModel")
        let modelPath = modelURL.path
        return try await withCheckedThrowingContinuation { continuation in
            self.whisperQueue.async {
                do {
                    let text = try self.runWhisperInference(modelPath: modelPath, samples: samples, language: language)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Transcribes the given WAV audio file using the local whisper.cpp model.
    /// - Parameter language: Optional whisper.cpp language code. Only applied to multilingual models.
    func transcribeAudioFile(_ audioFileURL: URL, language: String? = nil) async throws -> String {
        guard isDownloaded, let modelURL = modelPath else {
            throw NSError(domain: "WhisperModelManager", code: -9,
                         userInfo: [NSLocalizedDescriptionKey: "Whisper model not downloaded"])
        }

        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw NSError(domain: "WhisperModelManager", code: -10,
                         userInfo: [NSLocalizedDescriptionKey: "Audio file not found for transcription"])
        }

        // Load + resample to float32 16 kHz mono (what whisper.cpp expects)
        let samples = try extractAudioSamples(from: audioFileURL)
        logger.log("transcribeAudioFile: \(samples.count) samples loaded", category: "WhisperModel")

        // Run inference on the dedicated serial queue.
        // The context is loaded once and reused – no model reload between calls.
        let modelPath = modelURL.path
        return try await withCheckedThrowingContinuation { continuation in
            self.whisperQueue.async {
                do {
                    let text = try self.runWhisperInference(modelPath: modelPath, samples: samples, language: language)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Audio Resampling

    /// Reads an audio file and returns mono float32 samples at 16 kHz.
    private func extractAudioSamples(from url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let inputFormat = audioFile.processingFormat

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "WhisperModelManager", code: -11,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create 16kHz output format"])
        }

        // Read all input frames into a buffer
        let inputCapacity = AVAudioFrameCount(audioFile.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputCapacity) else {
            throw NSError(domain: "WhisperModelManager", code: -12,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to allocate input audio buffer"])
        }
        try audioFile.read(into: inputBuffer)

        // Allocate output buffer (scale capacity by sample-rate ratio)
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputCapacity) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw NSError(domain: "WhisperModelManager", code: -13,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output audio buffer"])
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(domain: "WhisperModelManager", code: -14,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format converter"])
        }

        var provided = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            guard !provided else {
                outStatus.pointee = .endOfStream
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        var convError: NSError?
        converter.convert(to: outputBuffer, error: &convError, withInputFrom: inputBlock)
        if let e = convError { throw e }

        guard let channelData = outputBuffer.floatChannelData else {
            throw NSError(domain: "WhisperModelManager", code: -15,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to get float channel data"])
        }

        let frameCount = Int(outputBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
    }

    // MARK: - Whisper Inference

    /// Must only be called from `whisperQueue`.
    /// - Parameter language: If the active model is multilingual (`language == "auto"`), this
    ///   override is applied. English-only and language-specific models ignore it.
    private func runWhisperInference(modelPath: String, samples: [Float], language: String? = nil) throws -> String {
        // Load context once; reuse on subsequent calls.
        if whisperCtx == nil {
            logger.log("Loading Whisper model context (first call)…", category: "WhisperModel")
            whisperCtx = whisper_init_from_file(modelPath)
        }
        guard let ctx = whisperCtx else {
            throw NSError(domain: "WhisperModelManager", code: -16,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to initialise Whisper context from model at \(modelPath)"])
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress   = false
        params.print_special    = false
        params.print_realtime   = false
        params.print_timestamps = false
        // For multilingual models, honour the user's language override; otherwise use the
        // language baked into the model spec (e.g. "en" for English-only, "yue" for Cantonese).
        let effectiveLanguage: String
        if selectedModel.language == "auto", let override = language, !override.isEmpty {
            effectiveLanguage = override
        } else {
            effectiveLanguage = selectedModel.language
        }
        params.language         = (effectiveLanguage as NSString).utf8String
        params.n_threads        = Int32(max(1, ProcessInfo.processInfo.processorCount - 1))

        let rc = samples.withUnsafeBufferPointer { ptr in
            whisper_full(ctx, params, ptr.baseAddress, Int32(ptr.count))
        }

        guard rc == 0 else {
            throw NSError(domain: "WhisperModelManager", code: -17,
                         userInfo: [NSLocalizedDescriptionKey: "Whisper inference failed with error code \(rc)"])
        }

        var result = ""
        let segmentCount = whisper_full_n_segments(ctx)
        for i in 0..<segmentCount {
            if let cStr = whisper_full_get_segment_text(ctx, i) {
                result += String(cString: cStr)
            }
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.log("Whisper transcription: \"\(trimmed)\"", category: "WhisperModel")
        return trimmed
    }
}
// MARK: - URLSessionDownloadDelegate for Progress Tracking

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressCallback: (Double) -> Void
    /// Destination path where the temp file should be moved immediately inside didFinishDownloadingTo.
    let destination: URL
    /// Fallback denominator when the server omits Content-Length (e.g. HuggingFace LFS CDN).
    let expectedFileSize: Int
    var continuation: CheckedContinuation<URLResponse, Error>? = nil
    private var lastLoggedPct: Int = -1

    init(destination: URL, expectedFileSize: Int, progressCallback: @escaping (Double) -> Void) {
        self.destination = destination
        self.expectedFileSize = expectedFileSize
        self.progressCallback = progressCallback
        super.init()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // IMPORTANT: URLSession deletes `location` as soon as this method returns.
        // We must move the file synchronously here before resuming the continuation.
        NSLog("[DL-Delegate] didFinishDownloadingTo: %@", location.path)
        do {
            // Remove stale destination if it somehow exists
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            NSLog("[DL-Delegate] File moved to destination: %@", destination.path)
        } catch {
            NSLog("[DL-Delegate] ERROR moving file: %@", error.localizedDescription)
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }
        guard let response = downloadTask.response else {
            NSLog("[DL-Delegate] ERROR: No response from server")
            continuation?.resume(throwing: NSError(domain: "WhisperModelManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "No response from server"]))
            continuation = nil
            return
        }
        continuation?.resume(returning: response)
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            NSLog("[DL-Delegate] didCompleteWithError: %@", error.localizedDescription)
            continuation?.resume(throwing: error)
            continuation = nil
        } else {
            NSLog("[DL-Delegate] didCompleteWithError called with nil error (task completed normally)")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // HuggingFace LFS CDN often returns -1 for totalBytesExpectedToWrite.
        // Fall back to the known model size so the progress bar still moves.
        let total: Int64 = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : Int64(expectedFileSize)
        guard total > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(total)
        let pct = Int(progress * 100)
        if pct != lastLoggedPct {
            lastLoggedPct = pct
            NSLog("[DL-Delegate] Progress: %d%% (%lld / %lld bytes)", pct, totalBytesWritten, total)
        }
        progressCallback(min(max(progress, 0.0), 1.0))
    }
}