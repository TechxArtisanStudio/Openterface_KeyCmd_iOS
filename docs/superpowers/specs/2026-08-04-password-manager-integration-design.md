# Password Manager Integration Design

**Date:** 2026-08-04  
**Status:** Draft  
**Author:** Claude (brainstorming session)

---

## Overview

Integrate iOS password management (iCloud Keychain and third-party password managers) with KeyCmd's API to allow users to select a password from their password vault and send it to the target computer via BLE KVM hardware.

## Use Case

When controlling a target computer through the Openterface KVM device, users need to enter passwords (e.g., login credentials, SSH passwords, application passwords). Instead of manually typing passwords on the iPhone keyboard, users can:

1. Tap the password button in the Keyboard & Mouse Pro view
2. Browse/select from all saved passwords in their password vault
3. The selected password is automatically sent to the target machine via BLE → KVM → HID

## Requirements

### Functional Requirements
- Support both iCloud Keychain and third-party password managers (1Password, Bitwarden, LastPass, etc.)
- Display all saved passwords in a searchable list
- Allow users to select a password and send it to the target machine
- Support Face ID / Touch ID authentication for secure password access
- No manual input required (no need to type domain/service name)
- Gracefully handle errors (password vault unavailable, user denied access, no passwords found)

### Non-Functional Requirements
- Security: Never store passwords locally; use system-level security mechanisms
- Performance: Password list should load within 1-2 seconds
- UX: Zero-input design - users should only need to tap and select
- Compatibility: iOS 17.0+ (matches app minimum requirement)

## Design Decisions

### Approach Selection

We evaluated three approaches:

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| **ASCredentialIdentityStore API** | No associated domains needed; supports all password managers; system-level security; simple implementation | Requires user authorization | ✅ **Selected** |
| Password AutoFill + Associated Domains | Best native UX | Requires server-side apple-app-site-association; not suitable for KVM (target machines have various domains) | ❌ Rejected |
| Third-party SDK Integration | Deep integration for specific managers | Requires separate SDKs; high maintenance; doesn't meet "support both" requirement | ❌ Rejected |

**Rationale:** ASCredentialIdentityStore is the best fit for KVM scenarios because:
- No associated domains configuration needed (critical since target machines have various domains)
- Can access both iCloud Keychain and all third-party password managers
- Simple implementation (~100-150 lines of code)
- High security (no local password storage)
- Good UX with system-native UI and biometric authentication

### UI Flow Decision

**Initial design:** Show an input dialog asking for service identifier (e.g., "github.com") → fetch credentials for that service → display password selection

**User feedback:** "Why do I need to input the service identifier? I want to tap the password button and directly see all available passwords."

**Updated design:** Fetch all password identities → display in searchable list → user selects → fetch actual password

**Rationale:** Zero-input design is better UX. Users don't need to remember or type domain names. The searchable list handles cases with many passwords.

## Architecture

### Components

#### 1. PasswordManager (New Service)
**Location:** `KeyCmd/Managers/PasswordManager.swift`

**Responsibilities:**
- Wrap AuthenticationServices API calls
- Handle password vault access and credential fetching
- Manage authorization state

**Public Interface:**
```swift
class PasswordManager: ObservableObject {
    static let shared = PasswordManager()
    
    @Published var isAvailable: Bool = false
    @Published var identities: [PasswordIdentity] = []
    
    func checkAvailability() -> Bool
    func requestAccess() async -> Bool
    func fetchIdentities() async throws -> [PasswordIdentity]
    func fetchPassword(for identity: PasswordIdentity) async throws -> String
}

struct PasswordIdentity: Identifiable, Hashable {
    let id: String
    let domain: String
    let username: String
}
```

#### 2. PasswordSelectionView (New View)
**Location:** `KeyCmd/View/Components/PasswordSelectionView.swift`

**Responsibilities:**
- Display searchable password list
- Handle password selection
- Show loading/error states

**UI Components:**
- Search bar (filter by domain/username)
- List view showing domain + username (not actual password)
- Loading indicator
- Error messages

**Example List:**
```
🔍 Search...

github.com
  john@example.com

work-server.company.com
  admin

apple.com
  user@icloud.com

bank.com
  customer123
```

#### 3. ComposeTextView (Modified)
**Location:** `KeyCmd/View/ComposeTextView.swift`

**Changes:**
- Add password button to action bar (left of send button)
- Integrate PasswordManager
- Handle password sending logic

**UI Layout:**
```
[Clear] [Save to Library] [Bookmark] [🔐 Password] ━━━ [Send]
```

### Data Flow

```
User taps password button
    ↓
Call PasswordManager.fetchIdentities()
    ↓
System prompts for Face ID/Touch ID
    ↓
Display password selection list (domain + username, searchable)
    ↓
User selects a password entry
    ↓
Call PasswordManager.fetchPassword(for: identity)
    ↓
Receive actual password string
    ↓
Call keyboardManager.handleTextInput(password)
    ↓
Password sent via BLE → KVM → Target machine
```

## Error Handling

| Scenario | Handling |
|----------|----------|
| Password vault unavailable | Show Alert: "Password manager is not enabled. Please enable it in Settings." |
| User denies authorization | Show Alert: "Password manager access required. Please grant permission in Settings." |
| No passwords found | Show Alert: "No passwords found in your vault." |
| User cancels selection | Silently close UI, don't send anything |
| BLE not connected | Reuse existing connection check logic, disable button |
| Password fetch fails | Show Alert: "Failed to retrieve password. Please try again." |
| Password send fails | Reuse existing send failure notification |

## Permissions & Configuration

### Frameworks
- `AuthenticationServices.framework` (system-provided, no additional download needed)

### Entitlements
- No additional configuration needed (ASCredentialIdentityStore doesn't require associated domains)

### Info.plist
- No additional configuration needed

### Capabilities
- None required (no iCloud, no associated domains)

## Testing Strategy

### Unit Tests

**PasswordManager Tests**
- Test `fetchIdentities()` returns correct password list
- Test `fetchPassword(for:)` correctly retrieves password
- Test error scenarios (vault unavailable, user denied, not found)
- Test empty list scenario

**Data Flow Tests**
- Test password correctly passed to `keyboardManager.handleTextInput()`
- Test error handling during send failure
- Test silent handling of user cancellation

### Integration Tests

**UI Tests**
- Test password button tap correctly shows password selection UI
- Test search bar filtering
- Test password selection correctly closes UI and sends
- Test cancellation correctly closes UI

**BLE Send Tests**
- Test password successfully sent to target machine
- Test button disabled when not connected
- Test cancel functionality during send

### Manual Testing Checklist

- [ ] Test on physical device (password manager requires Face ID/Touch ID)
- [ ] Test iCloud Keychain passwords
- [ ] Test third-party password manager (e.g., 1Password) passwords
- [ ] Test search filtering
- [ ] Test empty password list scenario
- [ ] Test password manager disabled scenario
- [ ] Test Face ID/Touch ID authorization flow
- [ ] Test successful password send (verify on target machine)

## Implementation Notes

### Key APIs

1. **Check availability:**
   ```swift
   let state = await ASCredentialIdentityStore.shared.state()
   if state.isEnabled { /* proceed */ }
   ```

2. **Fetch all password identities:**
   ```swift
   let identities = try await ASCredentialIdentityStore.shared.fetchIdentities()
   // identities contains ASCredentialIdentity objects with serviceIdentifier and user
   ```

3. **Fetch actual password:**
   ```swift
   let credential = try await ASCredentialIdentityStore.shared.fetchCredential(for: identity)
   let password = credential.password
   ```

4. **Send password:**
   ```swift
   keyboardManager.handleTextInput(password)
   ```

### Security Considerations

- Never log passwords
- Never store passwords in UserDefaults or local files
- Always use system-provided secure APIs
- Clear password from memory after sending (Swift handles this automatically for string literals)

### Performance Considerations

- Fetch identities asynchronously to avoid blocking UI
- Cache identity list for session duration (not persisted)
- Lazy load password content only when user selects an entry

## Future Enhancements

- **Recently used passwords:** Show recently selected passwords at the top
- **Favorites:** Allow users to mark certain passwords as favorites for quick access
- **Auto-send on select:** Send password immediately after selection (skip confirmation)
- **Username auto-fill:** Optionally send username before password
- **Password generator:** Generate strong passwords and offer to save to vault

## Open Questions

None - all requirements clarified and design approved.

---

## Appendix: API Reference

### AuthenticationServices Framework

**ASCredentialIdentityStore**
- `shared.state()` → Check if password vault is enabled
- `fetchIdentities()` → Get all saved password metadata
- `fetchCredential(for:)` → Get actual password for a specific identity

**ASPasswordCredentialIdentity**
- `serviceIdentifier` → Domain or service name
- `user` → Username or email
- `recordIdentifier` → Unique identifier

**ASPasswordCredential**
- `user` → Username
- `password` → Actual password string
