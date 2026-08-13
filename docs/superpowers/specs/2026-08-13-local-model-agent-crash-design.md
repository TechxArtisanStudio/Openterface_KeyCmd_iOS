# Fix: Local Qwen Agent crashes during inference and execution

## Problem

When the KeyCmd app uses a local Qwen model (Qwen3 0.6B or 1.7B via MLX Swift) as the AI provider and runs an Agent task, the app crashes without a visible error. The user reports:

- Both local Qwen models (0.6B and 1.7B) crash
- Running on an 8GB RAM iPhone (real device, not simulator)
- No crash logs are produced
- Crash occurs during or after Agent step execution

## Root Cause Analysis

### Primary issue: unsynchronized access to `modelContainer` and `chatSession`

`LocalModelManager.generate()` is called from multiple `Task`s in `AgentLLMService`:

- `handleLocalPlan` → `Task { LocalModelManager.shared.generate(...) }`
- `handleLocalSummarize` → `Task { LocalModelManager.shared.generate(...) }`
- `handleLocalRetryPlan` → `Task { LocalModelManager.shared.generate(...) }`

Inside `generate()`:

```swift
func generate(system: String, user: String) async throws -> String {
    if modelContainer == nil {                          // ⚠️ unsynchronized read
        state = .loading
        let container = try await loadModelContainer(configuration: config)
        await MainActor.run {
            self.modelContainer = container             // ⚠️ write via MainActor
            self.chatSession = ChatSession(container)
            self.state = .ready
        }
    }
    guard let container = modelContainer else { ... }   // ⚠️ another unsynchronized read
    let session = ChatSession(container)                // ⚠️ constructed on arbitrary Task thread
    return try await session.respond(to: prompt)        // ⚠️ inference on arbitrary Task thread
}
```

Three specific bugs:

1. **Race on first load**: if two Tasks call `generate()` before `modelContainer` is set, both enter the `if modelContainer == nil` branch and call `loadModelContainer` concurrently, which can corrupt MLX internal state.

2. **No happens-before guarantee**: `modelContainer` is written via `MainActor.run` but read from arbitrary Task threads. Without a synchronization barrier, the reads can observe stale or partially-written values.

3. **MLX thread affinity**: `ChatSession.respond(to:)` runs Metal command buffers. Metal command queues are thread-affine. Creating a `ChatSession` on one Task thread and calling `respond(to:)` on another (which happens naturally with Swift's cooperative thread pool) causes Metal validation errors that crash the app — often silently because Metal validation is disabled in Release builds.

### Secondary issue: `DispatchQueue.main.sync` deadlock risk in `AgentExecutor`

```swift
case "hid":
    keyboardManager.handleTextInputWithTokensSync(step.payload)
    DispatchQueue.main.sync { keyboardManager.releaseAllKeys() }  // ⚠️ can deadlock
    return nil
```

This runs on the `agent.executor` background queue. If any call chain ever invokes `execute(step:)` from the main thread (now or in the future), `DispatchQueue.main.sync` will deadlock immediately. The risk is latent but real.

## Fix Design

### Concurrency model

Use a **serial DispatchQueue + NSLock** (not a Swift `actor`):

- MLX Swift bridges to C/Metal, and `actor` isolation would force every access through async/await, complicating the `ObservableObject` pattern and the download flow.
- A serial queue for inference gives us the same serialization guarantee while keeping the download flow straightforward.
- An `NSLock` protects the read/write of `_modelContainer` and `_chatSession`.

### Changes to `LocalModelManager.swift`

#### 1. Add serial inference queue and lock

```swift
final class LocalModelManager: ObservableObject {
    static let shared = LocalModelManager()

    /// All MLX inference must run on this queue — Metal command queues
    /// are thread-affine, and ChatSession is not thread-safe.
    private let inferenceQueue = DispatchQueue(
        label: "com.keycmd.localmodel.inference",
        qos: .userInitiated
    )

    /// Protects _modelContainer and _chatSession.
    private let modelLock = NSLock()
    private var _modelContainer: ModelContainer?
    private var _chatSession: ChatSession?

    // Published state remains the same
    @Published private(set) var state: State = .notDownloaded
    @Published var modelSource: ModelSource { ... }
    @Published private(set) var activeModel: LocalModel
}
```

#### 2. Replace `generate()` with synchronized version

```swift
func generate(system: String, user: String) async throws -> String {
    guard isModelDownloaded() else {
        throw NSError(domain: "LocalModelManager", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Model not downloaded"])
    }

    // Ensure model container is loaded (idempotent, serialized)
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
```

#### 3. Add `ensureModelLoaded()` — serialized, idempotent

```swift
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
```

#### 4. Update `modelSource.didSet` and `selectModel(for:)` to reset under lock

```swift
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

func selectModel(for apiBaseURL: String) {
    guard let newModel = LocalModel.forBaseURL(apiBaseURL) else { return }
    guard newModel.id != activeModel.id else { return }
    activeModel = newModel
    modelLock.lock()
    _modelContainer = nil
    _chatSession = nil
    modelLock.unlock()
    checkIfModelDownloaded()
}
```

#### 5. Update download-success paths to also write via `modelLock`

The download functions (`startHFDownload`, `startModelScopeDownload`) currently write to `modelContainer` and `chatSession` directly. They need to be updated to write via `modelLock` for consistency with the rest of the class:

```swift
await MainActor.run {
    guard !Task.isCancelled else { return }
    self.modelLock.lock()
    self._modelContainer = container
    self._chatSession = ChatSession(container)
    self.modelLock.unlock()
    self.state = .downloaded
}
```

The download logic itself (file fetching, progress reporting) is unchanged — only the success assignment is wrapped with the lock.

### Changes to `AgentExecutor.swift` (defensive fix)

Replace the synchronous `DispatchQueue.main.sync` with async continuation so there's no deadlock risk:

```swift
case "hid":
    keyboardManager.handleTextInputWithTokensSync(step.payload)
    // Release all keys asynchronously to avoid deadlock risk
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        DispatchQueue.main.async {
            keyboardManager.releaseAllKeys()
            continuation.resume()
        }
    }
    return nil
```

This requires making `execute(step:)` async, which propagates up through `run(steps:...)`. The executor's `q.async` loop becomes a `for` with `try await execute(step:)`.

### Files to modify

| File | Change |
|---|---|
| `KeyCmd/AI/LocalModelManager.swift` | Add serial inference queue + lock; rewrite `generate()`, `ensureModelLoaded()`, `modelSource.didSet`, `selectModel(for:)`, download-success paths |
| `KeyCmd/Agent/AgentExecutor.swift` | Replace `DispatchQueue.main.sync` with async continuation in `execute(step:)` for HID case; make `execute` and `run` async |

### Files that do NOT need changes

- `AgentLLMService.swift` — the caller already awaits `LocalModelManager.shared.generate()` correctly
- `AgentSession.swift` — orchestrates Agent flow; no thread-safety concerns
- `AITextRefinementManager.swift` — doesn't route to local models; no changes needed (note: this may need local model routing in a future PR)

## Testing

### Automated

- **Concurrent load test**: call `generate()` N times concurrently from different Tasks; assert only one `loadModelContainer` is created
- **Source-switch test**: switch `modelSource` while inference is running; assert no crash, no use-after-free

### Manual on real device

1. Select "Local Qwen 0.6B" provider → submit an Agent task → approve → let it complete end-to-end (plan → execute → summarize) → verify no crash
2. Repeat with "Local Qwen 1.7B"
3. Submit an Agent task that produces failed steps → let retry trigger → verify no crash during retry
4. Rapidly switch between "Local Qwen 0.6B" and "Local Qwen 1.7B" while a task is running → verify no crash
5. Use local model for plan, then switch provider to a cloud model mid-flow → verify no crash

## Out of scope

- Adding crash reporter (PLCrashReporter) — can be a follow-up if the crash recurs after this fix
- Making `AITextRefinementManager` route to local models — separate feature
- Performance optimization (e.g., keeping the `ChatSession` warm between calls) — defer until correctness is confirmed
