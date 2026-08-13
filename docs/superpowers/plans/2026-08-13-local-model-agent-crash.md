# Local Model Agent Crash Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix crashes in KeyCmd when using local Qwen models (Qwen3 0.6B / 1.7B via MLX Swift) by serializing MLX inference and eliminating a latent deadlock in AgentExecutor.

**Architecture:** Introduce a serial `DispatchQueue` for all MLX inference calls and an `NSLock` to protect the shared `ModelContainer` / `ChatSession` state in `LocalModelManager`. This prevents concurrent inference on the same Metal command queue and eliminates race conditions during model loading. Separately, replace a `DispatchQueue.main.sync` call in `AgentExecutor` with an async continuation to remove deadlock risk.

**Tech Stack:** Swift 5.9+, iOS 17+, MLX Swift (`MLXLLM`, `MLXLMCommon`), Foundation (`DispatchQueue`, `NSLock`, `DispatchSemaphore`).

## Global Constraints

- iOS 17.0+ minimum deployment target
- MLX Swift `ChatSession` and `ModelContainer` are not thread-safe; all access must be serialized
- `LocalModelManager` remains an `ObservableObject` (not converted to Swift `actor`) for SwiftUI compatibility
- All `@Published` state updates continue to flow through `MainActor.run`
- No changes to `AgentLLMService.swift`, `AgentSession.swift`, or `AITextRefinementManager.swift`
- No new dependencies

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `KeyCmd/AI/LocalModelManager.swift` | Modify | Serialize MLX inference via serial queue + lock; protect `modelContainer` / `chatSession` with `NSLock` |
| `KeyCmd/Agent/AgentExecutor.swift` | Modify | Replace `DispatchQueue.main.sync` deadlock risk with async continuation in HID step |

---

### Task 1: Rewrite LocalModelManager with serial inference queue + lock

**Files:**
- Modify: `KeyCmd/AI/LocalModelManager.swift` (entire file)

**Interfaces:**
- Consumes: MLX Swift `ModelContainer`, `ModelConfiguration`, `ChatSession`, `loadModelContainer(configuration:)`
- Produces: `func generate(system:user:) async throws -> String` (same signature, thread-safe implementation)

**Context — Why this task exists:**
`LocalModelManager.generate()` is called from multiple `Task`s in `AgentLLMService` (`handleLocalPlan`, `handleLocalSummarize`, `handleLocalRetryPlan`). The current implementation reads/writes `modelContainer` without synchronization and constructs `ChatSession` on arbitrary cooperative thread pool threads. MLX Metal command queues are thread-affine — this causes crashes (often silent in Release builds where Metal validation is disabled).

- [ ] **Step 1: Add serial inference queue and lock properties**

Open `KeyCmd/AI/LocalModelManager.swift`. Inside the `LocalModelManager` class, add these two properties after `private var downloadTask: Task<Void, Never>?`:

```swift
/// All MLX inference must run on this queue — Metal command queues
/// are thread-affine, and ChatSession is not thread-safe.
private let inferenceQueue = DispatchQueue(
    label: "com.keycmd.localmodel.inference",
    qos: .userInitiated
)

/// Protects _modelContainer and _chatSession.
private let modelLock = NSLock()
```

- [ ] **Step 2: Rename stored properties to indicate they are lock-protected**

Replace the existing two properties:

```swift
private var modelContainer: ModelContainer?
private var chatSession: ChatSession?
```

With:

```swift
private var _modelContainer: ModelContainer?
private var _chatSession: ChatSession?
```

- [ ] **Step 3: Add `ensureModelLoaded()` — serialized, idempotent model loading**

Add this private method inside the class, above the existing `generate()` method:

```swift
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
```

- [ ] **Step 4: Rewrite `generate()` to use the serial inference queue**

Replace the existing `generate(system:user:)` method entirely with:

```swift
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
```

- [ ] **Step 5: Update `modelSource.didSet` to reset under lock**

Replace the existing `modelSource` property (with its `didSet`) with:

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
```

- [ ] **Step 6: Update `selectModel(for:)` to reset under lock**

Replace the existing `selectModel(for:)` method with:

```swift
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
```

- [ ] **Step 7: Update `deleteModel()` to reset under lock**

In the existing `deleteModel()` method, replace the block:

```swift
modelContainer = nil
chatSession = nil
```

With:

```swift
modelLock.lock()
_modelContainer = nil
_chatSession = nil
modelLock.unlock()
```

- [ ] **Step 8: Update the Hugging Face download success path**

In `startHFDownload()`, replace the success block inside `await MainActor.run { ... }`:

```swift
await MainActor.run {
    guard !Task.isCancelled else { return }
    self.modelContainer = container
    self.chatSession = ChatSession(container)
    self.state = .downloaded
}
```

With:

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

- [ ] **Step 9: Update the ModelScope download success path**

In `startModelScopeDownload()`, replace the success block inside `await MainActor.run { ... }`:

```swift
await MainActor.run {
    guard !Task.isCancelled else { return }
    self.modelContainer = container
    self.chatSession = ChatSession(container)
    self.state = .downloaded
}
```

With:

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

- [ ] **Step 10: Verify there are no remaining references to old property names**

Search the file for any remaining references to `modelContainer` or `chatSession` (without the leading underscore). The only occurrences should be `_modelContainer` and `_chatSession`. If any bare references remain, prefix them with `_` and wrap the access in `modelLock.lock()` / `modelLock.unlock()`.

Run:
```bash
grep -n 'modelContainer\|chatSession' KeyCmd/AI/LocalModelManager.swift | grep -v '_modelContainer\|_chatSession\|modelLock'
```

Expected: no output (or only comments / string literals).

- [ ] **Step 11: Build to verify compilation**

Run:
```bash
xcodebuild -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED` with no errors. If there are errors, fix them before proceeding.

- [ ] **Step 12: Commit LocalModelManager changes**

```bash
git add KeyCmd/AI/LocalModelManager.swift
git commit -m "fix: serialize MLX inference in LocalModelManager to prevent crash

Add serial DispatchQueue + NSLock to protect modelContainer/chatSession
from concurrent access by multiple Tasks (plan/summarize/retry).

- inferenceQueue serializes all ChatSession.respond(to:) calls
- modelLock protects reads/writes of _modelContainer and _chatSession
- ensureModelLoaded() is idempotent with double-check locking
- generate() bridges async inference to serial queue via DispatchSemaphore
- All write sites (didSet, selectModel, deleteModel, download paths) use lock

Root cause: MLX Metal command queues are thread-affine; concurrent
inference on the same container caused silent crashes in Release builds.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Fix AgentExecutor HID step deadlock risk

**Files:**
- Modify: `KeyCmd/Agent/AgentExecutor.swift`

**Interfaces:**
- Consumes: `KeyboardManager.handleTextInputWithTokensSync(_:)`, `KeyboardManager.releaseAllKeys()`
- Produces: `func execute(step:) async throws -> String?` (now async), `func run(steps:onStepStart:onStepDone:onDone:)` (loop updated to await async execute)

**Context — Why this task exists:**
`AgentExecutor.execute(step:)` for the `"hid"` case calls `DispatchQueue.main.sync { keyboardManager.releaseAllKeys() }`. This blocks the `agent.executor` background queue until the main queue runs the closure. If any call chain ever invokes `execute(step:)` from the main thread (now or in the future), `DispatchQueue.main.sync` deadlocks immediately. Replacing it with `DispatchQueue.main.async` wrapped in a continuation eliminates this risk.

- [ ] **Step 1: Make `execute(step:)` async and replace the sync dispatch**

In `KeyCmd/Agent/AgentExecutor.swift`, change the `execute(step:)` method signature and the `"hid"` case.

Change the method signature from:
```swift
private func execute(step: AgentLLMStep) -> String? {
```

To:
```swift
private func execute(step: AgentLLMStep) async throws -> String? {
```

Replace the `"hid"` case:
```swift
case "hid":
    keyboardManager.handleTextInputWithTokensSync(step.payload)
    // Safety: release all modifiers/keys so nothing carries into the next step.
    DispatchQueue.main.sync { keyboardManager.releaseAllKeys() }
    return nil
```

With:
```swift
case "hid":
    keyboardManager.handleTextInputWithTokensSync(step.payload)
    // Safety: release all modifiers/keys so nothing carries into the next step.
    // Use async continuation instead of DispatchQueue.main.sync to avoid
    // deadlock if execute(step:) is ever called from the main thread.
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        DispatchQueue.main.async {
            self.keyboardManager.releaseAllKeys()
            continuation.resume()
        }
    }
    return nil
```

- [ ] **Step 2: Update the `run(steps:...)` loop to await the async execute**

In the `run(steps:onStepStart:onStepDone:onDone:)` method, the loop body calls `self.execute(step: step)`. Change it to `try await`.

Replace:
```swift
let output = self.execute(step: step)
```

With:
```swift
let output: String?
do {
    output = try await self.execute(step: step)
} catch {
    LogManager.shared.log("Agent: step[\(idx)] execute failed: \(error.localizedDescription)", category: "Agent", level: .error)
    output = "Error: \(error.localizedDescription)"
}
```

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
xcodebuild -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 4: Commit AgentExecutor changes**

```bash
git add KeyCmd/Agent/AgentExecutor.swift
git commit -m "fix: replace DispatchQueue.main.sync in AgentExecutor HID step

DispatchQueue.main.sync from a background queue can deadlock if the call
chain ever reaches execute(step:) from the main thread. Replace with
DispatchQueue.main.async wrapped in an async continuation.

- execute(step:) is now async throws
- HID case uses withCheckedThrowingContinuation + main.async
- run(steps:...) loop updated to try await execute(step:)
- Errors from HID step are caught and reported as step output

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Manual verification on real device

**Files:** None (manual testing)

**Context — Why this task exists:**
The thread-safety fix addresses a crash that only manifests under specific conditions (concurrent MLX inference on a real device with Metal). Automated tests cannot easily reproduce this because MLX Swift requires a real Metal device. Manual verification on the user's 8GB RAM iPhone is the definitive test.

- [ ] **Step 1: Build and install on real iPhone**

Connect the iPhone via USB. In Xcode, select the device as the run destination and build + run the KeyCmd app.

- [ ] **Step 2: Test scenario 1 — Local Qwen 0.6B full Agent flow**

1. Open KeyCmd → Settings → AI Settings
2. Select provider "Local Qwen 0.6B"
3. If model is not downloaded, tap Download and wait for completion
4. Navigate to Agent view
5. Submit a prompt (e.g., "List the files in the current directory")
6. Approve the generated plan
7. Let execution complete (plan → execute → summarize)
8. Verify: no crash, summarize completes, result displayed

- [ ] **Step 3: Test scenario 2 — Local Qwen 1.7B full Agent flow**

1. Switch provider to "Local Qwen 1.7B"
2. Download the model if needed
3. Repeat the same Agent flow as Step 2
4. Verify: no crash

- [ ] **Step 4: Test scenario 3 — Agent with failed steps triggers retry**

1. With a local model selected, submit a prompt that is likely to produce a failing command (e.g., "Run a command that doesn't exist on the target")
2. Let the first step fail
3. Verify: retry plan is generated by the local model, no crash during retry
4. Let the full retry → execute → summarize flow complete

- [ ] **Step 5: Test scenario 4 — Rapid provider switching during activity**

1. Start an Agent task with "Local Qwen 0.6B"
2. While it's running (or during the approve screen), quickly switch the provider to "Local Qwen 1.7B" and back
3. Verify: no crash, app remains responsive

- [ ] **Step 6: Test scenario 5 — Switch from local to cloud mid-flow**

1. Submit an Agent task with a local model
2. After the plan is generated but before approving, switch to a cloud provider (e.g., OpenAI)
3. Approve and run
4. Verify: execution completes (summarize will use the new provider), no crash

- [ ] **Step 7: Test scenario 6 — HID mode Agent flow**

1. Ensure no terminal (SSH) profile is active — Agent should use HID (BLE keyboard) mode
2. With a local model selected, submit a prompt that generates HID steps
3. Verify: HID steps execute, no deadlock, no crash

- [ ] **Step 8: Commit any follow-up fixes if needed**

If any scenario reveals an issue, fix it and commit:

```bash
git add -A
git commit -m "fix: address issue found during manual verification of local model agent flow

[Describe the issue and fix]

Co-Authored-By: Claude <noreply@anthropic.com>"
```

If all scenarios pass, no commit needed — proceed to finishing the branch.

---

## Self-Review Checklist (for the implementer)

After completing all tasks, verify:

1. **No remaining bare `modelContainer` or `chatSession` references** — all accesses go through `_modelContainer` / `_chatSession` with `modelLock`
2. **All `@Published` state updates are via `MainActor.run`** — no direct assignments from background threads
3. **`generate()` is the only public inference entry point** — all three callers in `AgentLLMService` (`handleLocalPlan`, `handleLocalSummarize`, `handleLocalRetryPlan`) go through it
4. **`AgentExecutor.execute(step:)` has no synchronous main-queue calls** — all main-queue work uses `DispatchQueue.main.async`
5. **Build succeeds with no warnings** — `xcodebuild build` clean
