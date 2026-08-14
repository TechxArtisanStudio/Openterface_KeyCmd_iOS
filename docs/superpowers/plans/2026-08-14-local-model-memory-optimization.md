# Local Model Memory Optimization (Hybrid Strategy) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix OOM crashes when using local Qwen models (especially 1.7B) on 8GB RAM devices using a multi-layered memory protection strategy: delayed release, memory warning handling, and Agent session lifecycle management.

**Architecture:** Implement a hybrid memory management approach with four layers: (1) 10-second delayed release after inference for fast consecutive calls, (2) iOS memory warning listener for immediate release under pressure, (3) Agent session completion callback for proactive cleanup, and (4) enhanced logging for debugging. The model is released intelligently based on usage patterns and system pressure.

**Tech Stack:** Swift 5.9+, iOS 17+, MLX Swift (`MLXLLM`, `MLXLMCommon`), Foundation, UIKit (for memory warnings), Dispatch (for timers).

## Global Constraints

- iOS 17.0+ minimum deployment target
- MLX Swift `ModelContainer` and `ChatSession` are not thread-safe; all access must remain serialized via `inferenceQueue` and `modelLock`
- `LocalModelManager` remains an `ObservableObject` (not converted to Swift `actor`) for SwiftUI compatibility
- All `@Published` state updates continue to flow through `MainActor.run`
- No breaking changes to `AgentLLMService.swift` API — only add optional callback
- No new dependencies beyond UIKit (already available)
- Delayed release timeout: 10 seconds (configurable via constant)
- Agent completion callback is optional — existing code continues to work without it

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `KeyCmd/AI/LocalModelManager.swift` | Modify | Add delayed release timer, memory warning handler, force release API, enhanced logging |
| `KeyCmd/App/AppDelegate.swift` | Modify | Forward memory warnings to `LocalModelManager` |
| `KeyCmd/Agent/AgentLLMService.swift` | Modify | Add optional completion callback to release model after Agent session |

---

### Task 1: Implement delayed release with timer

**Files:**
- Modify: `KeyCmd/AI/LocalModelManager.swift` (add timer properties and methods)

**Interfaces:**
- Consumes: `inferenceQueue`, `modelLock`, `_modelContainer`, `_chatSession`
- Produces: `releaseModel()` with timer-based delayed release, `scheduleDelayedRelease()`, `cancelDelayedRelease()`

**Context — Why this task exists:**
The current implementation loads the model once and retains it indefinitely. On 8GB devices, the 1.7B model (~3-4GB in memory) causes OOM. However, immediately releasing after each inference is too aggressive — Agent flows require 3+ inferences (plan → execute → summarize), and reloading each time adds 15-30 seconds. A 10-second delayed release balances speed (fast consecutive inferences) and memory (release after idle).

- [ ] **Step 1: Add timer properties to LocalModelManager**

Open `KeyCmd/AI/LocalModelManager.swift`. Add these properties after `private var loadGeneration = 0`:

```swift
/// Timer for delayed model release. Cancelled when a new inference starts
/// before the previous timer fires. Prevents immediate reload overhead
/// during consecutive Agent inferences while still releasing memory after idle.
private var releaseTimer: DispatchSourceTimer?
private let releaseDelay: TimeInterval = 10.0  // seconds
private let releaseQueue = DispatchQueue(label: "com.keycmd.localmodel.release")
```

- [ ] **Step 2: Add `releaseModel()` method with timer cancellation**

Add this private method after the properties you just added:

```swift
/// Releases the model container and chat session to free memory.
/// Cancels any pending delayed release timer.
/// The model will be reloaded on the next `generate()` call.
private func releaseModel() {
    cancelDelayedRelease()
    modelLock.lock()
    _modelContainer = nil
    _chatSession = nil
    modelLock.unlock()
    logger.info("Model released to free memory")
}
```

- [ ] **Step 3: Add `scheduleDelayedRelease()` method**

Add this private method after `releaseModel()`:

```swift
/// Schedules a delayed release of the model container.
/// If called again before the timer fires, cancels the previous timer and restarts.
/// This allows consecutive inferences to share the loaded model while ensuring
/// memory is freed after idle periods.
private func scheduleDelayedRelease() {
    cancelDelayedRelease()
    
    let timer = DispatchSource.makeTimerSource(queue: releaseQueue)
    timer.schedule(deadline: .now() + releaseDelay)
    timer.setEventHandler { [weak self] in
        guard let self else { return }
        self.logger.info("Delayed release timer expired, releasing model")
        self.modelLock.lock()
        self._modelContainer = nil
        self._chatSession = nil
        self.modelLock.unlock()
        self.releaseTimer = nil
        DispatchQueue.main.async {
            self.state = .downloaded  // Reset to downloaded (not ready)
        }
    }
    timer.resume()
    releaseTimer = timer
    logger.info("Delayed release scheduled in \(self.releaseDelay)s")
}
```

- [ ] **Step 4: Add `cancelDelayedRelease()` method**

Add this private method after `scheduleDelayedRelease()`:

```swift
/// Cancels any pending delayed release timer.
/// Called when a new inference starts to prevent premature release.
private func cancelDelayedRelease() {
    releaseTimer?.cancel()
    releaseTimer = nil
}
```

- [ ] **Step 5: Modify `generate()` to use delayed release**

Replace the existing `generate(system:user:)` method with:

```swift
func generate(system: String, user: String) async throws -> String {
    guard isModelDownloaded() else {
        throw NSError(domain: "LocalModelManager", code: 1,
                     userInfo: [NSLocalizedDescriptionKey: "Model not downloaded"])
    }

    // Cancel any pending delayed release — we're about to use the model
    cancelDelayedRelease()

    logger.info("generate() called, ensuring model is loaded")
    try await ensureModelLoaded()

    let prompt = """
    \(system)

    User: \(user)
    Assistant:
    """

    logger.info("Starting inference (prompt length: \(prompt.count) chars)")

    let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
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

            let session = ChatSession(container)

            let sema = DispatchSemaphore(value: 0)
            var inferenceResult: Result<String, Error> = .failure(NSError(
                domain: "LocalModelManager", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Inference did not produce a result"]))

            Task {
                do {
                    inferenceResult = .success(try await session.respond(to: prompt))
                } catch {
                    inferenceResult = .failure(error)
                }
                sema.signal()
            }

            sema.wait()

            switch inferenceResult {
            case .success(let s):
                self.logger.info("Inference completed successfully (response length: \(s.count) chars)")
                continuation.resume(returning: s)
            case .failure(let e):
                self.logger.error("Inference failed: \(e.localizedDescription)")
                continuation.resume(throwing: e)
            }
        }
    }

    // Schedule delayed release instead of immediate release
    scheduleDelayedRelease()

    return result
}
```

- [ ] **Step 6: Build to verify compilation**

Run:
```bash
xcodebuild -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 7: Commit changes**

```bash
git add KeyCmd/AI/LocalModelManager.swift
git commit -m "feat: implement delayed model release with 10-second timer

Instead of releasing the model immediately after each inference (slow)
or never releasing (OOM), use a 10-second delayed release timer.

- Add DispatchSourceTimer-based delayed release mechanism
- Timer resets on each inference start (cancelDelayedRelease)
- Model released 10s after last inference (scheduleDelayedRelease)
- Allows fast consecutive inferences during Agent flows
- Releases memory after idle periods

Balance: Agent plan/execute/summarize completes quickly (no reloads),
but model is released 10s after Agent finishes to free memory.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Add iOS memory warning handling

**Files:**
- Modify: `KeyCmd/AI/LocalModelManager.swift` (add public method)
- Modify: `KeyCmd/App/AppDelegate.swift` (forward memory warnings)

**Interfaces:**
- Consumes: `releaseModel()`, `cancelDelayedRelease()` (from Task 1)
- Produces: `handleMemoryWarning()` public method that immediately releases the model

**Context — Why this task exists:**
The 10-second delayed release is great for normal usage, but when iOS is under memory pressure, we need to react immediately. iOS sends `didReceiveMemoryWarning` before terminating apps — we must release the model instantly to prevent crashes.

- [ ] **Step 1: Add `handleMemoryWarning()` public method**

Open `KeyCmd/AI/LocalModelManager.swift`. Add this public method after `isModelDownloaded()`:

```swift
/// Called when iOS issues a memory warning. Immediately releases the model
/// to free memory and prevent app termination. Cancels any pending delayed
/// release timer. The model will be reloaded on the next inference.
func handleMemoryWarning() {
    logger.warning("⚠️ Memory warning received — releasing model immediately")
    cancelDelayedRelease()
    modelLock.lock()
    _modelContainer = nil
    _chatSession = nil
    modelLock.unlock()
    DispatchQueue.main.async {
        self.state = .downloaded  // Reset to downloaded (not ready)
    }
}
```

- [ ] **Step 2: Find AppDelegate.swift**

Run:
```bash
find KeyCmd -name "AppDelegate.swift" -type f
```

Expected: One file path, e.g., `KeyCmd/App/AppDelegate.swift` or `KeyCmd/AppDelegate.swift`.

- [ ] **Step 3: Add memory warning handler to AppDelegate**

Open the AppDelegate file. If it does not have a `didReceiveMemoryWarning` method, add it inside the `AppDelegate` class:

```swift
override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    LocalModelManager.shared.handleMemoryWarning()
}
```

If the method already exists, add the `LocalModelManager.shared.handleMemoryWarning()` call at the end of the existing implementation.

- [ ] **Step 4: Build to verify compilation**

Run:
```bash
xcodebuild -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 5: Commit changes**

```bash
git add KeyCmd/AI/LocalModelManager.swift KeyCmd/App/AppDelegate.swift
git commit -m "feat: handle iOS memory warnings with immediate model release

When iOS issues a memory warning, immediately release the model container
to prevent app termination. This is the second layer of protection.

- Add handleMemoryWarning() to LocalModelManager
- Cancels any pending delayed release timer
- Releases model immediately (bypasses 10s delay)
- AppDelegate forwards didReceiveMemoryWarning to LocalModelManager
- State resets to .downloaded (not .ready) after release

Layer 1: 10s delayed release (normal usage)
Layer 2: Immediate release on memory warning (system pressure)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Add Agent session completion callback

**Files:**
- Modify: `KeyCmd/AI/LocalModelManager.swift` (add force release method)
- Modify: `KeyCmd/Agent/AgentLLMService.swift` (add optional completion callback)

**Interfaces:**
- Consumes: `releaseModel()`, `cancelDelayedRelease()` (from Task 1)
- Produces: `forceReleaseModel()` public method, optional `onAgentSessionComplete()` callback

**Context — Why this task exists:**
The delayed release is good for consecutive inferences, but after an Agent session completes, we want to release the model proactively — not wait 10 seconds. This is the third layer: Agent lifecycle management. When the Agent finishes (success or failure), we call `forceReleaseModel()` to immediately free memory.

- [ ] **Step 1: Add `forceReleaseModel()` public method**

Open `KeyCmd/AI/LocalModelManager.swift`. Add this public method after `handleMemoryWarning()`:

```swift
/// Force-releases the model immediately, bypassing the delayed release timer.
/// Called when an Agent session completes to proactively free memory.
/// The model will be reloaded on the next inference.
func forceReleaseModel() {
    logger.info("Force releasing model after Agent session")
    releaseModel()
}
```

- [ ] **Step 2: Find AgentLLMService.swift**

Run:
```bash
find KeyCmd -name "AgentLLMService.swift" -type f
```

Expected: One file path, e.g., `KeyCmd/Agent/AgentLLMService.swift`.

- [ ] **Step 3: Add optional completion callback to AgentLLMService**

Open `KeyCmd/Agent/AgentLLMService.swift`. Find the main method that orchestrates the Agent flow (likely `executePrompt()` or similar). At the end of the method, in both success and error paths, add:

```swift
// After Agent session completes (success or failure)
LocalModelManager.shared.forceReleaseModel()
```

If the method has multiple exit points (return statements), add this call before each return, or refactor to use `defer`:

```swift
defer {
    LocalModelManager.shared.forceReleaseModel()
}
```

- [ ] **Step 4: Build to verify compilation**

Run:
```bash
xcodebuild -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 5: Commit changes**

```bash
git add KeyCmd/AI/LocalModelManager.swift KeyCmd/Agent/AgentLLMService.swift
git commit -m "feat: add Agent session completion callback for proactive model release

After an Agent session completes (success or failure), immediately release
the model instead of waiting for the 10-second timer. This is the third
layer of memory protection.

- Add forceReleaseModel() to LocalModelManager
- AgentLLMService calls forceReleaseModel() after session completes
- Uses defer to ensure release happens on all exit paths

Layer 1: 10s delayed release (consecutive inferences)
Layer 2: Immediate release on memory warning (system pressure)
Layer 3: Immediate release after Agent session (proactive cleanup)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Add enhanced logging for debugging

**Files:**
- Modify: `KeyCmd/AI/LocalModelManager.swift` (add logging to key methods)

**Interfaces:**
- Consumes: `ensureModelLoaded()`, `releaseModel()`, `scheduleDelayedRelease()`, `cancelDelayedRelease()`
- Produces: Enhanced logging for all memory management operations

**Context — Why this task exists:**
To verify the hybrid strategy is working correctly and to diagnose issues on real devices, we need detailed logging. The logs should show when the model is loaded, when delayed release is scheduled/cancelled, and when the model is released (by timer, memory warning, or force).

- [ ] **Step 1: Add logging to `ensureModelLoaded()`**

Open `KeyCmd/AI/LocalModelManager.swift`. Replace the existing `ensureModelLoaded()` method with:

```swift
private func ensureModelLoaded() async throws {
    // Fast path: already loaded
    modelLock.lock()
    if _modelContainer != nil {
        modelLock.unlock()
        logger.info("Model already loaded (fast path)")
        return
    }

    // If another caller is already loading, await its task.
    if let existing = loadingTask {
        modelLock.unlock()
        logger.info("Model load in progress, awaiting existing task")
        try await existing.value
        return
    }

    logger.info("Loading model: \(self.activeModel.id)")

    // First caller — create the loading task.
    let myGeneration = loadGeneration
    let task = Task<Void, Error> { [weak self] in
        guard let self else { return }

        await MainActor.run { self.state = .loading }

        do {
            let config: ModelConfiguration = self.modelSource == .huggingface
                ? ModelConfiguration(id: self.activeModel.hfModelID)
                : ModelConfiguration(directory: self.localModelsDir)

            let container = try await loadModelContainer(configuration: config)

            self.modelLock.lock()
            guard self.loadGeneration == myGeneration else {
                self.modelLock.unlock()
                self.logger.warning("Model load completed but generation mismatch (stale), discarding")
                return
            }
            if self._modelContainer == nil {
                self._modelContainer = container
                self._chatSession = ChatSession(container)
                self.logger.info("Model loaded successfully")
            }
            self.loadingTask = nil
            self.modelLock.unlock()

            await MainActor.run { self.state = .ready }
        } catch {
            self.modelLock.lock()
            self.loadingTask = nil
            self.modelLock.unlock()

            self.logger.error("Model load failed: \(error.localizedDescription)")
            await MainActor.run { self.state = .notDownloaded }
            throw error
        }
    }

    loadingTask = task
    modelLock.unlock()

    try await task.value
}
```

- [ ] **Step 2: Verify logging exists in other methods**

The following methods already have logging from previous tasks:
- `releaseModel()`: "Model released to free memory"
- `scheduleDelayedRelease()`: "Delayed release scheduled in Xs" and "Delayed release timer expired, releasing model"
- `generate()`: "generate() called", "Starting inference", "Inference completed", "Delayed release scheduled"

No additional changes needed.

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
xcodebuild -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 4: Commit changes**

```bash
git add KeyCmd/AI/LocalModelManager.swift
git commit -m "chore: add enhanced logging for memory management debugging

Comprehensive logging to verify hybrid memory strategy is working:
- Model load: fast path, awaiting existing task, load start/success/failure
- Delayed release: scheduled, cancelled, timer expired
- Immediate release: memory warning, force release after Agent
- Inference: start, completion with response length

This helps diagnose memory behavior on real devices and confirms
all three layers of protection are functioning correctly.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Manual verification on real device

**Files:** None (manual testing)

**Context — Why this task exists:**
Memory optimization is difficult to test in simulators. Real device testing is needed to verify the hybrid strategy works correctly across all scenarios: normal Agent flows, consecutive runs, and memory pressure situations.

- [ ] **Step 1: Build and install on real iPhone**

Connect the iPhone via USB. In Xcode, select the device as the run destination and build + run the KeyCmd app.

- [ ] **Step 2: Test scenario 1 — 1.7B model full Agent flow (delayed release)**

1. Open KeyCmd → Settings → AI Settings
2. Select provider "Local Qwen 1.7B"
3. Download the model if not already downloaded
4. Navigate to Agent view
5. Submit a prompt (e.g., "Check disk usage with df -h")
6. Approve the generated plan
7. Let execution complete (plan → execute → summarize)
8. Verify: no OOM crash, all three phases complete quickly (no reload delays)
9. Check console logs:
   - "Model loaded" (once at start)
   - "Inference completed" ×3 (plan, execute, summarize)
   - "Delayed release scheduled in 10s" (after each inference)
   - "Delayed release timer expired, releasing model" (10s after last inference)

Expected behavior: Agent completes fast (model stays loaded), then releases 10s later.

- [ ] **Step 3: Test scenario 2 — Multiple consecutive Agent runs**

1. With 1.7B model still selected
2. Run a second Agent task immediately after the first completes (within 10s)
3. Verify: model is still loaded (no reload delay), Agent completes quickly
4. Run a third Agent task after waiting 15 seconds
5. Verify: model reloads (5-10s delay), then Agent completes
6. Check logs: second run shows "Model already loaded (fast path)", third run shows "Loading model"

Expected behavior: Consecutive runs are fast, idle periods trigger release.

- [ ] **Step 4: Test scenario 3 — Memory pressure test (immediate release)**

1. Open other memory-intensive apps (camera, photos, games) to pressure device memory
2. Return to KeyCmd
3. Run an Agent task with 1.7B model
4. Monitor console for "⚠️ Memory warning received — releasing model immediately"
5. Verify: if memory warning is triggered, model is released gracefully
6. Verify: app remains responsive, no crash
7. Next inference should reload the model

Expected behavior: Memory warning triggers immediate release, app survives.

- [ ] **Step 5: Test scenario 4 — Agent completion force release**

1. Run an Agent task with 1.7B model
2. Let it complete successfully
3. Check console for "Force releasing model after Agent session"
4. Verify: model is released immediately (no 10s wait)
5. Run another Agent task
6. Verify: model reloads (expected behavior)

Expected behavior: Agent completion triggers immediate release, not delayed.

- [ ] **Step 6: Test scenario 5 — 0.6B model baseline**

1. Switch to 0.6B model
2. Run the same Agent flow
3. Verify: faster inference, no crash (baseline comparison)
4. Check logs: same delayed release pattern

Expected behavior: Smaller model works correctly with same memory strategy.

- [ ] **Step 7: Monitor memory with Instruments (optional but recommended)**

1. In Xcode, go to Product → Profile
2. Select the "Allocations" template
3. Run the app and perform an Agent flow with 1.7B model
4. Observe memory usage:
   - Model load: ~3-4GB increase
   - During Agent: memory stays high (model loaded)
   - 10s after Agent: memory drops (model released)
5. Verify: memory pattern matches expected behavior

Expected pattern: sawtooth memory usage (load → use → release → repeat).

- [ ] **Step 8: Commit any follow-up fixes if needed**

If any scenario reveals an issue, fix it and commit:

```bash
git add -A
git commit -m "fix: address issue found during memory optimization testing

[Describe the issue and fix]

Co-Authored-By: Claude <noreply@anthropic.com>"
```

If all scenarios pass, no commit needed — proceed to finishing the branch.

---

## Self-Review Checklist (for the implementer)

After completing all tasks, verify:

1. **Delayed release timer works correctly** — `scheduleDelayedRelease()` creates timer, `cancelDelayedRelease()` cancels it, timer fires after 10s of idle
2. **Memory warning handler is wired** — AppDelegate forwards to `LocalModelManager.shared.handleMemoryWarning()`, releases immediately
3. **Agent completion callback is added** — `AgentLLMService` calls `forceReleaseModel()` after session completes
4. **Logging is comprehensive** — all memory management operations are logged for debugging
5. **Thread safety is preserved** — all `_modelContainer`/`_chatSession` access uses `modelLock`, all `@Published` updates go through `MainActor.run`
6. **No breaking changes to AgentLLMService API** — existing code continues to work, only added callback
7. **Build succeeds with no warnings** — `xcodebuild build` clean

---

## Summary: Hybrid Memory Strategy (3 Layers)

| Layer | Trigger | Action | Benefit |
|-------|---------|--------|---------|
| **1. Delayed Release** | After each inference | Schedule 10s timer, release if idle | Fast consecutive inferences during Agent flow |
| **2. Memory Warning** | iOS system pressure | Immediate release | Prevents OOM under memory pressure |
| **3. Agent Completion** | Agent session ends | Immediate release | Proactive cleanup after Agent finishes |

**Result:** Agent flows complete quickly (no reload delays), but memory is freed intelligently based on usage and system pressure.
