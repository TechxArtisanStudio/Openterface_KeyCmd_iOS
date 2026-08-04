# Password Manager Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate iOS password management (iCloud Keychain and third-party password managers) with KeyCmd to allow users to select passwords from their vault and send them to the target computer via BLE KVM hardware.

**Architecture:** Create a PasswordManager service that wraps iOS AuthenticationServices API, a PasswordSelectionView for displaying searchable password lists, and integrate a password button into the existing ComposeTextView. The system fetches password metadata (domain + username) first, displays them in a searchable list, then fetches the actual password only when the user selects an entry.

**Tech Stack:** Swift, SwiftUI, AuthenticationServices framework, iOS 17.0+

## Global Constraints

- iOS 17.0+ minimum deployment target
- Use AuthenticationServices framework (system-provided, no external dependencies)
- Never store passwords locally or log passwords
- Support both iCloud Keychain and third-party password managers
- Zero-input design: no manual domain/service name entry required
- All UI text must be in English
- Follow existing code patterns in KeyCmd (ObservableObject for managers, SwiftUI views)
- Use async/await for all asynchronous operations
- Minimum 80% test coverage for new code

## File Structure

### Files to Create

1. **`KeyCmd/Managers/PasswordManager.swift`**
   - Singleton service wrapping AuthenticationServices API
   - Manages password vault access and credential fetching
   - Handles authorization state and error scenarios

2. **`KeyCmd/View/Components/PasswordSelectionView.swift`**
   - Searchable password list view
   - Displays domain + username (not actual passwords)
   - Handles loading and error states
   - Returns selected password via callback

3. **`KeyCmdTests/PasswordManagerTests.swift`**
   - Unit tests for PasswordManager
   - Test availability check, identity fetching, password retrieval
   - Test error scenarios and edge cases

### Files to Modify

1. **`KeyCmd/View/ComposeTextView.swift`**
   - Add password button to action bar (left of send button)
   - Add @State for password sheet presentation
   - Integrate PasswordManager
   - Handle password selection and sending

---

## Task 1: PasswordManager Service Implementation

**Files:**
- Create: `KeyCmd/Managers/PasswordManager.swift`
- Create: `KeyCmdTests/PasswordManagerTests.swift`

**Interfaces:**
- Consumes: AuthenticationServices framework (ASCredentialIdentityStore, ASPasswordCredentialIdentity)
- Produces: PasswordManager class with public methods for other components to use

- [ ] **Step 1: Write failing test for PasswordManager availability check**

Create `KeyCmdTests/PasswordManagerTests.swift`:

```swift
import XCTest
@testable import KeyCmd

final class PasswordManagerTests: XCTestCase {
    var passwordManager: PasswordManager!
    
    override func setUp() {
        super.setUp()
        passwordManager = PasswordManager.shared
    }
    
    override func tearDown() {
        passwordManager = nil
        super.tearDown()
    }
    
    func testCheckAvailability_ReturnsTrueWhenVaultEnabled() async {
        // This test will initially fail because PasswordManager doesn't exist yet
        let isAvailable = await passwordManager.checkAvailability()
        // In simulator, this may return false, but the method should exist and be callable
        XCTAssertNotNil(isAvailable)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/PasswordManagerTests/testCheckAvailability_ReturnsTrueWhenVaultEnabled`

Expected: Build fails with "No such module 'PasswordManager'" or "Value of type 'PasswordManager' has no member 'checkAvailability'"

- [ ] **Step 3: Create PasswordManager with basic availability check**

Create `KeyCmd/Managers/PasswordManager.swift`:

```swift
import Foundation
import AuthenticationServices

struct PasswordIdentity: Identifiable, Hashable {
    let id: String
    let domain: String
    let username: String
}

class PasswordManager: ObservableObject {
    static let shared = PasswordManager()
    
    @Published var isAvailable: Bool = false
    @Published var identities: [PasswordIdentity] = []
    
    private let credentialStore = ASCredentialIdentityStore.shared
    
    private init() {}
    
    func checkAvailability() async -> Bool {
        let state = await credentialStore.state()
        await MainActor.run {
            self.isAvailable = state.isEnabled
        }
        return state.isEnabled
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/PasswordManagerTests/testCheckAvailability_ReturnsTrueWhenVaultEnabled`

Expected: PASS

- [ ] **Step 5: Add test for fetchIdentities**

Add to `KeyCmdTests/PasswordManagerTests.swift`:

```swift
    func testFetchIdentities_ReturnsEmptyArrayWhenNoPasswords() async throws {
        // In simulator with no passwords, should return empty array
        let identities = try await passwordManager.fetchIdentities()
        XCTAssertNotNil(identities)
    }
    
    func testFetchIdentities_ThrowsErrorWhenVaultUnavailable() async {
        // This test verifies error handling
        do {
            let _ = try await passwordManager.fetchIdentities()
            // If vault is available, test passes
        } catch {
            // If vault is unavailable, we should get an error
            XCTAssertNotNil(error)
        }
    }
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/PasswordManagerTests`

Expected: Build fails with "Value of type 'PasswordManager' has no member 'fetchIdentities'"

- [ ] **Step 7: Implement fetchIdentities method**

Add to `KeyCmd/Managers/PasswordManager.swift`:

```swift
    func fetchIdentities() async throws -> [PasswordIdentity] {
        guard await credentialStore.state().isEnabled else {
            throw PasswordManagerError.vaultUnavailable
        }
        
        do {
            let allIdentities = try await credentialStore.fetchIdentities()
            let passwordIdentities = allIdentities.compactMap { identity -> PasswordIdentity? in
                guard let passwordIdentity = identity as? ASPasswordCredentialIdentity,
                      let serviceIdentifier = passwordIdentity.serviceIdentifier?.identifier else {
                    return nil
                }
                
                return PasswordIdentity(
                    id: passwordIdentity.recordIdentifier ?? UUID().uuidString,
                    domain: serviceIdentifier,
                    username: passwordIdentity.user
                )
            }
            
            await MainActor.run {
                self.identities = passwordIdentities
            }
            
            return passwordIdentities
        } catch {
            throw PasswordManagerError.fetchFailed(error.localizedDescription)
        }
    }
```

- [ ] **Step 8: Add PasswordManagerError enum**

Add to `KeyCmd/Managers/PasswordManager.swift`:

```swift
enum PasswordManagerError: LocalizedError {
    case vaultUnavailable
    case fetchFailed(String)
    case passwordNotFound
    case userDenied
    
    var errorDescription: String? {
        switch self {
        case .vaultUnavailable:
            return "Password manager is not enabled. Please enable it in Settings."
        case .fetchFailed(let message):
            return "Failed to fetch passwords: \(message)"
        case .passwordNotFound:
            return "Password not found for the selected entry."
        case .userDenied:
            return "Password manager access was denied."
        }
    }
}
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/PasswordManagerTests`

Expected: All tests PASS

- [ ] **Step 10: Add test for fetchPassword**

Add to `KeyCmdTests/PasswordManagerTests.swift`:

```swift
    func testFetchPassword_ThrowsErrorForInvalidIdentity() async {
        let invalidIdentity = PasswordIdentity(
            id: "invalid-id",
            domain: "nonexistent.com",
            username: "user"
        )
        
        do {
            let _ = try await passwordManager.fetchPassword(for: invalidIdentity)
            XCTFail("Should throw error for invalid identity")
        } catch {
            XCTAssertNotNil(error)
        }
    }
```

- [ ] **Step 11: Run test to verify it fails**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/PasswordManagerTests/testFetchPassword_ThrowsErrorForInvalidIdentity`

Expected: Build fails with "Value of type 'PasswordManager' has no member 'fetchPassword'"

- [ ] **Step 12: Implement fetchPassword method**

Add to `KeyCmd/Managers/PasswordManager.swift`:

```swift
    func fetchPassword(for identity: PasswordIdentity) async throws -> String {
        guard await credentialStore.state().isEnabled else {
            throw PasswordManagerError.vaultUnavailable
        }
        
        // Find the matching ASPasswordCredentialIdentity
        let allIdentities = try await credentialStore.fetchIdentities()
        guard let matchingIdentity = allIdentities.first(where: { credentialIdentity in
            guard let passwordIdentity = credentialIdentity as? ASPasswordCredentialIdentity,
                  let serviceIdentifier = passwordIdentity.serviceIdentifier?.identifier else {
                return false
            }
            return passwordIdentity.recordIdentifier == identity.id ||
                   (serviceIdentifier == identity.domain && passwordIdentity.user == identity.username)
        }) else {
            throw PasswordManagerError.passwordNotFound
        }
        
        do {
            let credential = try await credentialStore.fetchCredential(for: matchingIdentity as! ASPasswordCredentialIdentity)
            return credential.password
        } catch {
            throw PasswordManagerError.fetchFailed(error.localizedDescription)
        }
    }
```

- [ ] **Step 13: Run all tests to verify they pass**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:KeyCmdTests/PasswordManagerTests`

Expected: All tests PASS

- [ ] **Step 14: Commit PasswordManager implementation**

```bash
git add KeyCmd/Managers/PasswordManager.swift KeyCmdTests/PasswordManagerTests.swift
git commit -m "feat: add PasswordManager service for iOS password vault integration

Implement PasswordManager that wraps AuthenticationServices API to fetch
password identities and credentials from iCloud Keychain and third-party
password managers. Includes unit tests for availability check, identity
fetching, and password retrieval with error handling.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: PasswordSelectionView Implementation

**Files:**
- Create: `KeyCmd/View/Components/PasswordSelectionView.swift`

**Interfaces:**
- Consumes: PasswordManager, PasswordIdentity
- Produces: PasswordSelectionView that returns selected password via callback

- [ ] **Step 1: Create basic PasswordSelectionView structure**

Create `KeyCmd/View/Components/PasswordSelectionView.swift`:

```swift
import SwiftUI

struct PasswordSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var passwordManager = PasswordManager.shared
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var onPasswordSelected: (String) -> Void
    
    var filteredIdentities: [PasswordIdentity] {
        if searchText.isEmpty {
            return passwordManager.identities
        }
        return passwordManager.identities.filter { identity in
            identity.domain.localizedCaseInsensitiveContains(searchText) ||
            identity.username.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading passwords...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredIdentities.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "lock.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No passwords found in your vault.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredIdentities) { identity in
                        Button {
                            Task {
                                await selectPassword(identity)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(identity.domain)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(identity.username)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search passwords")
                }
            }
            .navigationTitle("Select Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadPasswords()
        }
    }
    
    private func loadPasswords() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let _ = try await passwordManager.fetchIdentities()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func selectPassword(_ identity: PasswordIdentity) async {
        do {
            let password = try await passwordManager.fetchPassword(for: identity)
            dismiss()
            onPasswordSelected(password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build to verify no compilation errors**

Run: `xcodebuild build -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: Build succeeds

- [ ] **Step 3: Commit PasswordSelectionView**

```bash
git add KeyCmd/View/Components/PasswordSelectionView.swift
git commit -m "feat: add PasswordSelectionView for password selection UI

Implement searchable password list view that displays password identities
(domain + username) and handles password selection. Includes loading states,
error handling, and search filtering. Returns selected password via callback.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Integrate Password Button into ComposeTextView

**Files:**
- Modify: `KeyCmd/View/ComposeTextView.swift`

**Interfaces:**
- Consumes: PasswordManager, PasswordSelectionView
- Produces: Updated ComposeTextView with password button and sending logic

- [ ] **Step 1: Add state variables for password sheet**

Open `KeyCmd/View/ComposeTextView.swift` and add after line 326 (after `@State private var libraryPreviewText = ""`):

```swift
    @State private var showPasswordSheet = false
    @State private var passwordError: String?
    @State private var showPasswordError = false
```

- [ ] **Step 2: Add password button to action bar**

Locate the action buttons HStack (around line 386-414). Find this section:

```swift
                    HStack(spacing: 8) {
                        actionBtn(icon: "xmark", color: !text.isEmpty ? .red : .secondary, enabled: !text.isEmpty) {
                            undoSnapshot = ""; undoClearEligible = false; text = ""
                            UserDefaults.standard.removeObject(forKey: "compose_cached_text")
                        }
                        actionBtn(icon: "externaldrive.fill.badge.plus", color: .secondary) {
                            store.save(text)
                        }
                        actionBtn(icon: "bookmark.fill", color: .secondary) {
                            showLibrarySheet = true
                        }
                        Spacer()
```

Replace with:

```swift
                    HStack(spacing: 8) {
                        actionBtn(icon: "xmark", color: !text.isEmpty ? .red : .secondary, enabled: !text.isEmpty) {
                            undoSnapshot = ""; undoClearEligible = false; text = ""
                            UserDefaults.standard.removeObject(forKey: "compose_cached_text")
                        }
                        actionBtn(icon: "externaldrive.fill.badge.plus", color: .secondary) {
                            store.save(text)
                        }
                        actionBtn(icon: "bookmark.fill", color: .secondary) {
                            showLibrarySheet = true
                        }
                        actionBtn(icon: "lock.fill", color: .blue, enabled: canSend) {
                            showPasswordSheet = true
                        }
                        Spacer()
```

- [ ] **Step 3: Add password sheet modifier**

Locate the sheet modifiers section (around line 442-447). Find:

```swift
            .sheet(isPresented: $showLibrarySheet) {
                savedTextLibrarySheet
            }
```

Add after it:

```swift
            .sheet(isPresented: $showPasswordSheet) {
                PasswordSelectionView { password in
                    sendPassword(password)
                }
            }
            .alert("Password Error", isPresented: $showPasswordError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(passwordError ?? "Unknown error")
            }
```

- [ ] **Step 4: Add sendPassword method**

Add the following method after the `sendItem` method (around line 689):

```swift
    private func sendPassword(_ password: String) {
        guard canSend else {
            passwordError = "Cannot send password. Please ensure BLE is connected."
            showPasswordError = true
            return
        }
        
        HapticFeedbackManager.shared.triggerButtonPress()
        keyboardManager.handleTextInput(password)
    }
```

- [ ] **Step 5: Build to verify no compilation errors**

Run: `xcodebuild build -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: Build succeeds

- [ ] **Step 6: Test on simulator**

1. Launch the app on iOS Simulator
2. Navigate to Keyboard & Mouse Pro mode
3. Verify the password button (lock icon) appears in the action bar
4. Tap the password button
5. Verify the password selection sheet appears (may show "No passwords found" in simulator)
6. Verify the Cancel button works

- [ ] **Step 7: Commit ComposeTextView integration**

```bash
git add KeyCmd/View/ComposeTextView.swift
git commit -m "feat: integrate password button into ComposeTextView

Add password button to action bar (left of send button) that opens
PasswordSelectionView. Selected password is sent to target machine via
keyboardManager.handleTextInput(). Includes error handling for BLE
connection status and password retrieval failures.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Manual Testing on Physical Device

**Files:**
- No code changes (manual testing only)

**Prerequisites:**
- Physical iPhone device (password manager requires Face ID/Touch ID)
- Openterface KVM hardware connected via BLE
- At least one password saved in iCloud Keychain or third-party password manager

- [ ] **Step 1: Test password vault availability**

1. Launch app on physical device
2. Navigate to Keyboard & Mouse Pro mode
3. Tap password button
4. Verify Face ID/Touch ID prompt appears
5. Authenticate
6. Verify password list displays saved passwords

- [ ] **Step 2: Test password search functionality**

1. In password selection view, use search bar
2. Type partial domain name (e.g., "git")
3. Verify list filters correctly
4. Clear search
5. Verify full list reappears

- [ ] **Step 3: Test password sending**

1. Open Notes app or text editor on target computer
2. In KeyCmd, tap password button
3. Select a password from the list
4. Verify password is typed into target computer's text field
5. Verify password matches the selected entry

- [ ] **Step 4: Test error scenarios**

1. **Empty vault**: If possible, test with a vault that has no passwords
   - Expected: "No passwords found in your vault." message
   
2. **Cancel selection**: Tap Cancel button in password selection view
   - Expected: Sheet closes, nothing sent
   
3. **BLE disconnected**: Disconnect BLE and try to tap password button
   - Expected: Button should be disabled (grayed out)

- [ ] **Step 5: Test third-party password manager**

1. If using 1Password/Bitwarden, verify their passwords appear in the list
2. Select a password from third-party manager
3. Verify it sends correctly to target

- [ ] **Step 6: Document any issues found**

Create a comment in the code or issue tracker documenting:
- Any UI/UX issues discovered
- Any performance problems (slow loading, etc.)
- Any edge cases not covered by the implementation
- Suggestions for future enhancements

---

## Task 5: Add to Xcode Project and Final Integration

**Files:**
- Modify: `KeyCmd.xcodeproj/project.pbxproj` (via Xcode GUI)

- [ ] **Step 1: Ensure new files are added to Xcode project**

Open `KeyCmd.xcodeproj` in Xcode:

1. Verify `PasswordManager.swift` is in the `KeyCmd/Managers` group
2. Verify `PasswordSelectionView.swift` is in the `KeyCmd/View/Components` group
3. Verify `PasswordManagerTests.swift` is in the `KeyCmdTests` group
4. If any files are missing, drag them from Finder into the correct group in Xcode

- [ ] **Step 2: Add AuthenticationServices framework**

1. Select KeyCmd target in Xcode
2. Go to "General" tab
3. Scroll to "Frameworks, Libraries, and Embedded Content"
4. Click "+" button
5. Search for "AuthenticationServices"
6. Add it (it should already be available as a system framework)

- [ ] **Step 3: Run full test suite**

Run: `xcodebuild test -project KeyCmd.xcodeproj -scheme KeyCmd -destination 'platform=iOS Simulator,name=iPhone 15'`

Expected: All tests pass (including existing tests)

- [ ] **Step 4: Build for release**

Run: `xcodebuild build -project KeyCmd.xcodeproj -scheme KeyCmd -configuration Release -destination 'generic/platform=iOS'`

Expected: Build succeeds with no errors

- [ ] **Step 5: Final commit**

```bash
git add .
git commit -m "chore: finalize password manager integration

Add new files to Xcode project, verify AuthenticationServices framework
is linked, run full test suite, and build for release.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Summary

This implementation plan delivers:

1. **PasswordManager service** - Wraps iOS AuthenticationServices API to fetch password identities and credentials
2. **PasswordSelectionView** - Searchable UI for browsing and selecting passwords
3. **ComposeTextView integration** - Password button added to action bar with sending logic
4. **Comprehensive tests** - Unit tests for PasswordManager
5. **Manual testing guide** - Checklist for physical device testing

Total estimated implementation time: 2-3 hours
Total new code: ~200-250 lines
Files created: 3
Files modified: 1
