import Foundation
import os
import MLXLLM
import MLXLMCommon

/// Represents a locally-runnable MLX model.
struct LocalModel: Identifiable, Hashable {
    let id: String              // matches the apiBaseURL suffix, e.g. "qwen3-1.7b"
    let displayName: String
    let hfModelID: String
    let modelScopeBaseURL: String
    let files: [String]
    let approxSizeMB: Int

    static let all: [LocalModel] = [
        LocalModel(
            id: "qwen3-0.6b",
            displayName: "Qwen3 0.6B",
            hfModelID: "mlx-community/Qwen3-0.6B-4bit",
            modelScopeBaseURL: "https://modelscope.cn/models/mlx-community/Qwen3-0.6B-4bit/resolve/main/",
            files: ["config.json", "tokenizer.json", "tokenizer_config.json",
                    "model.safetensors"],
            approxSizeMB: 400
        ),
        LocalModel(
            id: "qwen3-1.7b",
            displayName: "Qwen3 1.7B",
            hfModelID: "mlx-community/Qwen3-1.7B-4bit",
            modelScopeBaseURL: "https://modelscope.cn/models/mlx-community/Qwen3-1.7B-4bit/resolve/main/",
            files: ["config.json", "tokenizer.json", "tokenizer_config.json",
                    "model.safetensors"],
            approxSizeMB: 1100
        ),
    ]

    /// Resolve a LocalModel from an apiBaseURL like "local://qwen3-1.7b".
    static func forBaseURL(_ url: String) -> LocalModel? {
        guard url.hasPrefix("local://") else { return nil }
        let suffix = String(url.dropFirst("local://".count))
        return all.first { $0.id == suffix }
    }
}

/// Manages on-device Qwen model download, loading, and inference via MLX Swift.
/// Uses MLXLLM for model loading and ChatSession for text generation.
final class LocalModelManager: ObservableObject {
    static let shared = LocalModelManager()

    private let logger = Logger(subsystem: "com.keycmd.app", category: "LocalModelManager")

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .notDownloaded

    // MARK: - Model Source

    enum ModelSource: String, CaseIterable, Codable {
        case huggingface = "Hugging Face"
        case modelscope = "ModelScope"

        var displayName: String { rawValue }
    }

    /// Persisted model source preference
    @Published var modelSource: ModelSource {
        didSet {
            guard oldValue != modelSource else { return }
            UserDefaults.standard.set(modelSource.rawValue, forKey: "LocalModelManager.modelSource")
            modelLock.lock()
            _modelContainer = nil
            _chatSession = nil
            modelLock.unlock()
            checkIfModelDownloaded()
        }
    }

    // MARK: - Configuration

    /// The currently active model (driven by the selected AI provider's apiBaseURL).
    @Published private(set) var activeModel: LocalModel

    /// Local directory for ModelScope downloads
    private lazy var localModelsDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("local-models", isDirectory: true)
            .appendingPathComponent(activeModel.id, isDirectory: true)
    }()

    private var _modelContainer: ModelContainer?
    private var _chatSession: ChatSession?
    private var downloadTask: Task<Void, Never>?

    /// All MLX inference must run on this queue — Metal command queues
    /// are thread-affine, and ChatSession is not thread-safe.
    private let inferenceQueue = DispatchQueue(
        label: "com.keycmd.localmodel.inference",
        qos: .userInitiated
    )

    /// Protects _modelContainer and _chatSession.
    private let modelLock = NSLock()

    var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    private init() {
        let savedSource = UserDefaults.standard.string(forKey: "LocalModelManager.modelSource")
        self.modelSource = ModelSource(rawValue: savedSource ?? "") ?? .modelscope
        // Default to the smallest model for quick testing
        self.activeModel = LocalModel.all.first { $0.id == "qwen3-0.6b" } ?? LocalModel.all[0]
        logger.info("LocalModelManager initialized, modelSource: \(self.modelSource.rawValue), activeModel: \(self.activeModel.id)")
        checkIfModelDownloaded()
    }

    // MARK: - Model Selection

    /// Switch the active model. Call this when the user selects a different local provider.
    /// Resets cached containers and re-checks download status for the new model.
    func selectModel(for apiBaseURL: String) {
        guard let newModel = LocalModel.forBaseURL(apiBaseURL) else { return }
        guard newModel.id != activeModel.id else { return }
        logger.info("selectModel: \(self.activeModel.id) -> \(newModel.id)")
        activeModel = newModel
        modelLock.lock()
        _modelContainer = nil
        _chatSession = nil
        modelLock.unlock()
        checkIfModelDownloaded()
    }

    // MARK: - Public API

    /// Ensures the MLX model container is loaded. Idempotent — if already
    /// loaded, returns immediately. Serialized via `modelLock` so concurrent
    /// callers do not trigger duplicate loads.
    private func ensureModelLoaded() async throws {
        // Fast path: already loaded
        modelLock.lock()
        let alreadyLoaded = _modelContainer != nil
        modelLock.unlock()
        guard !alreadyLoaded else { return }

        await MainActor.run { state = .loading }

        do {
            let config: ModelConfiguration = modelSource == .huggingface
                ? ModelConfiguration(id: activeModel.hfModelID)
                : ModelConfiguration(directory: localModelsDir)

            let container = try await loadModelContainer(configuration: config)

            modelLock.lock()
            // Double-check: another Task may have loaded it while we were awaiting
            if _modelContainer == nil {
                _modelContainer = container
                _chatSession = ChatSession(container)
            }
            modelLock.unlock()

            await MainActor.run { state = .ready }
        } catch {
            await MainActor.run { state = .notDownloaded }
            throw error
        }
    }

    func startDownload() {
        logger.info("startDownload() called, modelSource: \(self.modelSource.rawValue), model: \(self.activeModel.id), state: \(String(describing: self.state))")
        guard !isDownloading, state != .downloaded else { return }
        state = .downloading(progress: 0.0)

        // Clean up any leftover temp files from previous attempts
        try? cleanupModelScopeTempFiles()

        switch modelSource {
        case .huggingface:
            logger.info("Routing to Hugging Face download")
            startHFDownload()
        case .modelscope:
            logger.info("Routing to ModelScope download")
            startModelScopeDownload()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .notDownloaded
    }

    func deleteModel() {
        downloadTask?.cancel()
        downloadTask = nil
        modelLock.lock()
        _modelContainer = nil
        _chatSession = nil
        modelLock.unlock()

        switch modelSource {
        case .huggingface:
            let config = ModelConfiguration(id: activeModel.hfModelID)
            let dir = config.modelDirectory(hub: defaultHubApi)
            logger.info("deleteModel (HF): removing \(dir.path)")
            try? FileManager.default.removeItem(at: dir)
        case .modelscope:
            logger.info("deleteModel (MS): removing \(self.localModelsDir.path)")
            try? FileManager.default.removeItem(at: localModelsDir)
        }
        state = .notDownloaded
    }

    func generate(system: String, user: String) async throws -> String {
        guard isModelDownloaded() else {
            throw NSError(domain: "LocalModelManager", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Model not downloaded"])
        }

        try await ensureModelLoaded()

        let prompt = """
        \(system)

        User: \(user)
        Assistant:
        """

        // Run inference on the serial queue so only one MLX session
        // is active at a time, and always on the same queue.
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            inferenceQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(
                        domain: "LocalModelManager", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "LocalModelManager deallocated"]))
                    return
                }

                self.modelLock.lock()
                let container = self._modelContainer
                self.modelLock.unlock()

                guard let container else {
                    continuation.resume(throwing: NSError(
                        domain: "LocalModelManager", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Model container not initialized"]))
                    return
                }

                // A fresh ChatSession per inference to prevent KV cache
                // corruption across plan / summarize / retry calls.
                let session = ChatSession(container)

                // Bridge async respond(to:) to the serial queue via semaphore.
                // We block the queue thread until inference completes so the
                // next caller cannot enter until this inference finishes —
                // otherwise the async block would return immediately and a
                // second inference could start concurrently on the same container.
                let sema = DispatchSemaphore(value: 0)
                var result: Result<String, Error> = .failure(NSError(
                    domain: "LocalModelManager", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Inference did not produce a result"]))

                Task {
                    do {
                        result = .success(try await session.respond(to: prompt))
                    } catch {
                        result = .failure(error)
                    }
                    sema.signal()
                }

                sema.wait()

                switch result {
                case .success(let s): continuation.resume(returning: s)
                case .failure(let e): continuation.resume(throwing: e)
                }
            }
        }
    }

    func isModelDownloaded() -> Bool {
        if case .downloaded = state { return true }
        if case .ready = state { return true }
        return false
    }

    // MARK: - Download from Hugging Face

    private func startHFDownload() {
        logger.info("startHFDownload() called, modelID: \(self.activeModel.hfModelID)")
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let config = ModelConfiguration(id: activeModel.hfModelID)
                logger.info("Calling loadModelContainer with id: \(self.activeModel.hfModelID)")
                let container = try await loadModelContainer(
                    configuration: config,
                    progressHandler: { [weak self] progress in
                        let pct = progress.fractionCompleted.isFinite
                            ? min(max(progress.fractionCompleted, 0.0), 1.0) : 0.0
                        DispatchQueue.main.async { [weak self] in
                            guard let self, case .downloading = self.state else { return }
                            self.state = .downloading(progress: pct)
                        }
                    }
                )
                logger.info("loadModelContainer succeeded")
                try Task.checkCancellation()
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.modelLock.lock()
                    self._modelContainer = container
                    self._chatSession = ChatSession(container)
                    self.modelLock.unlock()
                    self.state = .downloaded
                }
            } catch {
                logger.error("HF download failed: \(error.localizedDescription)")
                await MainActor.run { self.state = .error(error.localizedDescription) }
            }
            await MainActor.run { self.downloadTask = nil }
        }
    }

    // MARK: - Download from ModelScope

    private func startModelScopeDownload() {
        logger.info("startModelScopeDownload() called for model: \(self.activeModel.id)")
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                logger.info("Starting downloadModelScopeFiles()")
                try await downloadModelScopeFiles()
                try Task.checkCancellation()
                logger.info("downloadModelScopeFiles() completed, loading model container")

                let config = ModelConfiguration(directory: localModelsDir)
                let container = try await loadModelContainer(configuration: config)

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.modelLock.lock()
                    self._modelContainer = container
                    self._chatSession = ChatSession(container)
                    self.modelLock.unlock()
                    self.state = .downloaded
                }
            } catch is CancellationError {
                await MainActor.run { self.state = .notDownloaded }
            } catch {
                logger.error("ModelScope download failed: \(error.localizedDescription)")
                await MainActor.run { self.state = .error(error.localizedDescription) }
            }
            await MainActor.run { self.downloadTask = nil }
        }
    }

    private func cleanupModelScopeTempFiles() {
        guard case .modelscope = modelSource else { return }
        let enumerator = FileManager.default.enumerator(at: localModelsDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "tmp" {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func downloadModelScopeFiles() async throws {
        logger.info("downloadModelScopeFiles() starting, localModelsDir: \(self.localModelsDir.path)")
        try FileManager.default.createDirectory(at: localModelsDir, withIntermediateDirectories: true)

        let total = Double(activeModel.files.count)
        for (i, file) in activeModel.files.enumerated() {
            try Task.checkCancellation()
            let dest = localModelsDir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: dest.path) {
                logger.info("File \(file) already exists, skipping")
                continue
            }

            let url = URL(string: "\(activeModel.modelScopeBaseURL)\(file)")!
            logger.info("Downloading \(file) from \(url.absoluteString)")

            // Use download(from:) — downloads to a temp file on disk, not memory
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.error("Failed to download \(file), status: \(statusCode)")
                throw NSError(domain: "ModelScope", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to download \(file) (HTTP \(statusCode))"])
            }

            // Move temp file to final destination
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)
            logger.info("Downloaded \(file)")

            let pct = Double(i + 1) / total
            await MainActor.run {
                guard case .downloading = self.state else { return }
                self.state = .downloading(progress: pct)
            }
        }
        logger.info("All ModelScope files downloaded successfully")
    }

    // MARK: - State

    private func checkIfModelDownloaded() {
        switch modelSource {
        case .huggingface:
            let config = ModelConfiguration(id: activeModel.hfModelID)
            // Use the same hub API as loadModelContainer (caches directory, not documents)
            let dir = config.modelDirectory(hub: defaultHubApi)
            let exists = FileManager.default.fileExists(atPath: dir.path)
            logger.info("checkIfModelDownloaded (HF): model=\(self.activeModel.id), dir=\(dir.path), exists=\(exists)")
            state = exists ? .downloaded : .notDownloaded
        case .modelscope:
            let exists = FileManager.default.fileExists(atPath: localModelsDir.path)
            logger.info("checkIfModelDownloaded (MS): model=\(self.activeModel.id), dir=\(self.localModelsDir.path), exists=\(exists)")
            state = exists ? .downloaded : .notDownloaded
        }
    }
}
