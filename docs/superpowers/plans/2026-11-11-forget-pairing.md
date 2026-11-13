# Forget Pairing (app-side reset + system guidance)

Date: 2026-11-11
Status: implemented (2026-11-11); switched to reading the PIN from the device on 2026-11-12; real-device verification pending
Predecessor: [2026-11-10 BLE pairing PIN and bond management](2026-11-10-ble-pairing-pin.md)

## 1. Goal

After changing the pairing PIN, get back to an "unpaired" state quickly so the new PIN can be tested.

## 2. iOS capability limits

| Capability | Supported | Conclusion |
|---|---|---|
| App removes the iOS system Bluetooth bond | No | Can only point the user to Settings > Bluetooth > Forget This Device |
| App clears its own pairing records | Yes | Clears `lastConnectedUUID/Name`, `pairedDeviceUUIDs` (`pinChangedUUIDs` was removed on 2026-11-12 along with §11) |
| Clear device bonds over BLE with `0x22 0x02` | Yes | But it restores the PIN to 666666, so it cannot be used when testing a custom PIN |

The feature is therefore defined as: **disconnect and clear all app-side records, stop scanning and
auto-reconnect, then show the system-settings steps**. `0x22 0x02` is never sent, so the new PIN
survives the test cycle.

## 3. Implementation

### 3.1 BLEManager

- New `forgetPairing()`:
  - runs on `bleQueue`, sets `suppressAutoReconnect`, and ends any in-flight rename/ECM/security window;
  - `stopScanning()` + `cancelPeripheralConnection`;
  - clears `ble_last_connected_uuid/name` and `ble_paired_device_uuids`;
  - keeps `ble_known_device_uuids` (custom-named devices would otherwise become undiscoverable) and
    `ble_pin_changed_device_uuids` (forgetting pairing does not reset the device PIN, so clearing this
    would falsely warn "may still be 666666"; removed on 2026-11-12 with §11);
  - resets `connectionState / lastConnectedDeviceName / isWaitingForPairing / pairingIssue / showFactoryPINReminder / securityState` on the main thread.
- New internal static `clearLocalPairingState()` so it can be unit tested.
- The auto-connect branch in `didDiscover` now checks `suppressAutoReconnect`, so scanning does not
  immediately reconnect after the state is cleared; manually tapping a device goes through
  `beginConnecting`, which resets the flag, so it is unaffected.

### 3.2 BLESecuritySheet

- New "Forget pairing on this iPhone" section below "Change PIN":
  - asks for confirmation and explains that it disconnects, stops scanning and clears app records,
    while iOS keeps the system bond;
  - after confirmation shows a result page: system-settings steps, device name copy, and a reminder to
    re-pair in the app with the new PIN;
  - if the device still refuses to pair, suggests resetting the device bonds over USB.

### 3.3 Factory-PIN reminder switch

- `BLEManager.factoryPINReminderKey` / `factoryPINReminderEnabled`: on by default; the first-connection
  reminder in `finalizeConnection` now honours the switch.
- `Settings > General` gains a "Bluetooth pairing" section with a "Remind me to change the factory pairing PIN" toggle.
- The reminder banner lives at the top level of `ContentView` (under the top bar, only while connected);
  `ConnectionDialogView` only handles connecting and closes itself after successful encryption, so it
  cannot host the reminder. The banner has a "Change" action (opens `BLESecuritySheet` directly) and a
  dismiss button, and it hides immediately when the switch is turned off.
- The reset success page now states explicitly "Pairing PIN restored to 666666". The device does not
  report the current PIN, so the reminder could only be a one-shot inference at "first connection and
  this app has never changed the PIN".
  (2026-11-12: after firmware added `0x22 0x07` to read the PIN, the reminder is based on the actual
  value read back — see §11.)
- When a reconnect hits `CBError.peerRemovedPairingInformation` (bonds cleared on the device side), the
  local `paired/pinChanged` flags are cleared; clearing bonds on this firmware always resets the PIN, so
  the factory reminder reappears on the next connection. This also makes the app remind again after
  `0x22 0x02` is run from the USB side. (The `pinChanged` flag was removed on 2026-11-12.)
- Setting the PIN to `666666` via "Change PIN" no longer records it in `pinChangedUUIDs` and shows the
  reminder again; `setPIN` only passes a boolean to the BLE queue, so the PIN plaintext is never retained.

### 3.4 Localization

12 strings added to `en / zh-Hans / zh-Hant / ja / ko / fr`.

## 4. Tests

- Unit tests: `clearLocalPairingState()` clears the 3 keys and keeps known UUIDs plus the PIN-changed flag
  (the latter was removed on 2026-11-12; the test now asserts known UUIDs are kept).
- `plutil -lint` over the 6 `Localizable.strings` files.
- `xcodebuild test` (iPhone 17 Pro simulator).
- Real-device verification pending: change PIN → forget pairing → ignore in system settings → rescan → enter the new PIN.

## 5. File list

- [x] `KeyCmd/Managers/BLEManager.swift`
- [x] `KeyCmd/View/ContentView.swift` (top-level factory-PIN reminder banner)
- [x] `KeyCmd/View/Connection/BLESecuritySheet.swift`
- [x] `KeyCmd/View/Connection/ConnectionDialogView.swift`
- [x] `KeyCmd/View/GeneralSettingsView.swift`
- [x] `KeyCmd/Resources/Localizations/*.lproj/Localizable.strings` × 6
- [x] `KeyCmdTests/BLEManagerTests.swift`
- [x] This plan's status and checkboxes

## 6. Verification

- [x] `plutil -lint` passes for all 6 `Localizable.strings`
- [x] `BLEManagerTests` 14 tests pass (including forget pairing and the factory-PIN reminder switch)
- [x] Full `xcodebuild test` passes (406 tests, 0 failures)
- [ ] Real device: change PIN → forget pairing → ignore in system settings → rescan → enter the new PIN
- [ ] Real device: reset to 666666 → reconnect → warn on the main screen → "Change" opens PIN editing directly

## 7. Implementation log (2026-11-11)

- `BLEManager.forgetPairing()`: sets `suppressAutoReconnect`, stops scanning, disconnects; clears
  `lastConnectedUUID/Name` and `pairedDeviceUUIDs`, keeps `knownDeviceUUIDs` and `pinChangedUUIDs`;
  resets connection/pairing/security state on the main thread.
- The auto-connect branch in `didDiscover` now checks `suppressAutoReconnect`, so scanning does not
  immediately reconnect after forgetting; tapping a device manually still works.
- `BLESecuritySheet` gains the "Forget pairing on this iPhone" section, a confirmation step and a result
  page (system-settings steps, device-name copy, re-pair with the new PIN hint).
- `0x22 0x02` is not sent: that command restores the PIN to 666666, which conflicts with "test a changed PIN".
- New `factoryPINReminderEnabled` switch (on by default); the General page can turn the factory reminder
  off; the reset success page states "Pairing PIN restored to 666666".
- When the device clears bonds (`peerRemovedPairingInformation`), the local PIN-changed flag is cleared too,
  so the factory reminder reappears after a USB-side reset.
- Fixed an invisible reminder: `finalizeConnection` set the reminder while closing the connection dialog,
  and the banner only rendered inside that dialog. It is now a global banner under the `ContentView` top
  bar (only while connected) whose "Change" opens `BLESecuritySheet`; the duplicate banner inside
  `ConnectionDialogView` was removed.
- Fixed "no reminder after setting the PIN back to 666666": on a successful `setPIN`, if the new PIN is
  666666 it is not recorded in `pinChangedUUIDs` and the reminder flag is re-armed; only a boolean is passed,
  the PIN plaintext is never retained.
- The PIN-change confirmation moved from the top of the page to directly below the Save button
  (`BLESecuritySheet.pinSection`), so it stays visible while the user is at the button. Firmware
  `0x22 0x04` only affects the next pairing and does not drop existing bonds, so reconnecting right after
  a PIN change is expected.

## 8. Possible follow-up (needs firmware support)

A true "clear bonds on both sides while keeping the new PIN" needs a new firmware command that erases
bonds but preserves the PIN override; the existing `0x22 0x02` cannot do that. iOS system bonds can still
only be removed by the user in Settings > Bluetooth.

## 9. PIN sharing (implemented 2026-11-11, superseded by §11)

> 2026-11-12: the Keychain cache + manual entry approach in this section was replaced by "read the PIN
> from the device" in §11; `PairingPINStore` and the manual-entry UI were both removed.

- Entry point: a persistent `Pairing PIN` section on the `Pairing & Security` page; as long as the app had
  cached that device's PIN, it could be viewed, copied or shared at any time, without changing the PIN first.
- Rationale: the firmware never reported the current PIN, so the app only knew it at the moment the user
  entered and saved it. "Share at any time" therefore required caching the last value set on this device.
- Storage: `PairingPINStore` (Keychain, service `com.openterface.keycmd.pairing-pin`, account = device UUID).
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, no sync, no logging, no UserDefaults. It only cached PINs
  this app had set itself.
- Write points:
  - `0x22 0x04` set-PIN success → cache the new PIN;
  - `0x22 0x02` reset (including the stale-bond inference in `clearPairingHistory`) → cache 666666.
- "Forget pairing" did not delete the cache: the device PIN is unchanged, and "change PIN → forget →
  re-pair" is exactly the flow that needs the value for viewing/sharing; consistent with keeping
  `pinChangedUUIDs`. The cache was only overwritten with 666666 when the device was actually reset.
- Staleness risk: if the PIN was changed by another phone or over USB, the cache could not know; the page
  showed the fixed note "Last PIN set by this app… may be out of date if changed elsewhere."
- After a successful save, "Pairing PIN updated." still appeared below the Save button while the
  `Pairing PIN` section switched to the new value immediately; the next save briefly entered `.savingPIN`.
- Localization: added `Pairing PIN` and the staleness note; removed the old "PIN stays on this page" copy.
- Verification: `PairingPINStoreTests` covered save/update/delete/per-device isolation; the full
  `xcodebuild test` passed.
- Real-device verification pending: change PIN → kill the app → relaunch → still shareable on
  Pairing & Security; forget pairing → cache remains (device PIN unchanged).
- Fixed "second open of `Pairing & Security` only shows Forget": the change/reset sections depended on a
  local `bondStatus` assigned only when `onChange` saw `.ready`. On reopening, the device state had not
  changed, so `.loading → .ready` could be coalesced by SwiftUI into one render, the callback never fired,
  and `bondStatus` stayed nil. It now reads `BLEManager.pairingStatus` (set on `.ready`, cleared on
  `.erased`/`.unsupportedFirmware`), so the page shows it immediately without relying on one-shot events.
- Fixed the missing share entry: the `Pairing PIN` section only rendered when `cachedPairingPIN != nil`, and
  the cache was only filled after this app successfully ran `0x22 0x04`; a PIN set by an older build or
  another phone had no cache, so the page offered no sharing at all. It became a persistent section:
  - with a cache → show the PIN plus `Edit` / `Copy` / `Share PIN`;
  - without a cache → show a one-shot input where the user enters the current PIN and taps
    `Save for Sharing`, writing to the same Keychain (`BLEManager.rememberPairingPIN`) without sending
    `0x22 0x04` or changing the device PIN;
  - the copy stated clearly "the device does not report the PIN" and "stored only on this device".
- Verification: `plutil -lint` passed for the 6 localization files; full `xcodebuild test` passed (401 tests).

## 10. Device-identifier discovery (implemented 2026-11-11)

- Problem: the original discovery logic required the advertised name to start with `openterface` / `kvm` /
  `keymod`, so any custom name (e.g. `MyDevice`) dropped the device from the scan list.
- Firmware fact (`APP/peripheral.c`): before appending the runtime name, `advertData` always writes
  `GAP_ADTYPE_16BIT_MORE` + `SIMPLEPROFILE_SERV_UUID` (`0xFFF0`, `Profile/include/gattprofile.h`).
  Names are at most 20 characters and editable; the service UUID never changes.
- iOS reads that UUID through `CBAdvertisementDataServiceUUIDsKey`, independent of the device name.
- Implementation:
  - `BLEManager.serviceUUID = CBUUID(string: "FFF0")`, reused by `discoverServices`.
  - `isDiscoverableDevice(name:identifier:advertisedServices:)`: if the advertisement contains `FFF0`,
    accept any name; the name prefix is only a fallback for old firmware that does not advertise the UUID;
    finally still accept `lastConnectedUUID` / `knownDeviceUUIDs`.
  - `didDiscover` reads the advertised services from
    `advertisementData[CBAdvertisementDataServiceUUIDsKey]` and passes them in.
  - `shouldAutoConnect`: known device UUIDs auto-connect directly; name comparison prefers the advertised
    name, so iOS's cached `peripheral.name` cannot go stale after a rename.
  - Scanning itself still does not filter services: old firmware without the `FFF0` advertisement is still
    found by name prefix.
- Known trade-off: `0xFFF0` is a common experimental service UUID (e.g. HM-10 modules). Such devices may
  appear in the scan list but fail to connect because they lack `FFF1/FFF2`; this is the most stable
  identifier available when iOS cannot read MAC addresses.
- Tests: `testDiscoverableByAdvertisedServiceUUIDForAnyName` covers any name + `FFF0` being discoverable
  and foreign services still being rejected.

## 11. Reading the PIN from the device (implemented 2026-11-12)

- User feedback: sharing the PIN should not require manual entry; the PIN should be read from the Bluetooth
  device and be copyable or revealable in a popup; old firmware has no PIN concept and must not raise a
  "change PIN" reminder.
- Firmware (`Openterface_KM/APP/peripheral.c`; requires reflashing, the firmware project was not built as
  part of this change):
  - added CH9329 `0x22 0x07` to read the effective PIN via `BLE_PairConfig_GetEffectivePin()`
    (factory `666666` or the USB-side override);
  - replies `A2 [status][6 ASCII digits]`, failures use `E2`;
  - `uint8_t response[4]` widened to `[8]` to hold the 7-byte reply.
- Protocol layer (`BLESecurityCommand`):
  - `readPINFrame()` = `57 AB 00 22 01 07 2C`;
  - `parsePIN(_:)` requires exactly 6 ASCII digits, otherwise nil.
- `BLEManager`:
  - `devicePIN` is memory-only (never persisted, never logged); plus `isReadingPairingPIN`;
  - `fetchSecurityStatus()` (`0x03`) chains a `0x07` on success; `0x04` success re-reads, so the UI shows
    the value the device actually applies;
  - the factory reminder is now based on the read result: it only shows when this app is connecting for the
    first time (`pendingFactoryReminderCheck`) and the PIN read is exactly `666666`;
  - old firmware (`0x07` rejected or timed out) → silently clears `devicePIN`, no error, no reminder;
  - when `0x03` is unsupported, `pairingStatus == nil` and the whole PIN section is hidden;
  - switching devices, disconnecting, forgetting pairing or resetting clears all PIN state.
- Old-firmware compatibility (added 2026-11-12):
  - connections no longer probe `0x03` unconditionally: only "first connection with the factory reminder
    enabled" probes, avoiding an extra round trip on every connection and a 5-second security window held
    open on firmware without `0x22` support;
  - the PIN section renders only when a value was read or a read is in progress; after a rejected/timed-out
    `0x07` the section disappears entirely — no warning, no Retry, no manual read entry point;
  - `0x03` returning `[00,00]` (old firmware stub) is treated as "no pairing PIN"; the page shows the
    neutral note "This device firmware has no pairing PIN. Pairing is handled by iOS Settings > Bluetooth."
    instead of "reset bonds over USB";
  - outcome: on old firmware (the pre-2026-11-10 `0x22` stub) connecting, keyboard/touch, rename and ECM
    are unaffected by the PIN feature.
- UI (`BLESecuritySheet`, rendered only when `pairingStatus != nil` and a PIN was read):
  - with a value → `••••••` plus an eye icon; tapping opens an `.alert` with the PIN; `Copy` copies and
    shows "PIN copied." inline; `Share PIN` uses `ShareLink`; a note explains "read from the device, applies
    to the next pairing";
  - while reading → "Reading pairing PIN..." with a progress bar.
- Removed: `PairingPINStore` (Keychain), `PairingPINStoreTests`, `pinChangedUUIDs` and
  `hasChangedPIN` / `markPINChanged` / `clearPINChanged`, plus the manual-entry copy.
- Localization: 9 stale strings removed, 4 new strings × 6 languages; the reminder banner now states a fact
  ("This device still uses the factory PIN 666666", since it only shows after reading 666666); the old
  "pairing management unsupported / USB reset" note was replaced by "no pairing PIN, pairing is handled by
  iOS Settings".
- Verification: `plutil -lint` passes for the 6 files; full `xcodebuild test` passes (411 tests), with new
  `readPINFrame` / `parsePIN` / scanner-parsing tests.
- Real-device verification pending: new firmware → Pairing & Security shows the device PIN automatically;
  tap shows the popup; copy/share work; old firmware → no PIN section, no factory reminder, no error, and
  everything else still works.

## 12. Fixing the false factory-PIN reminder (2026-11-12)

- Symptom: the device PIN was already changed to `888888`, but connecting from a new phone still warned
  "the current PIN is 666666, please change it".
- Cause: the new phone was running a pre-`0x07` build (`da6da95`) whose criterion was
  `firstConnection && !hasPINChanged` — on a fresh install `hasPINChanged` is necessarily false, so the
  very first connection warned unconditionally without ever reading the real device PIN. That build cannot
  be corrected remotely; the new phone must install the current build.
- Criterion in the current build (`BLEManager`):
  - `showFactoryPINReminder` is only set when `0x22 0x07` actually reads back `666666`;
  - reading any other value (e.g. `888888`) also clears an existing banner, so it self-corrects;
  - new `reminderDeviceID`: the banner belongs to the device that reported it — kept when reconnecting to
    the same unit, cleared immediately when switching devices (fixing the cross-device leak); also cleared
    on disconnect, forget pairing and reset.
- Verification: `xcodebuild test` 411 passed. Real-device check: tap the masked PIN on the Pairing & Security
  page — it shows the device's actual value; if it reads `888888` while the banner is still there, the phone
  is not running the current build.
