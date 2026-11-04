# BLE-Eth Protocol Specification

> **Version**: 2.0
> **Last updated**: 2026-11-03 (audited against the iOS implementation; sections 2, 4 and
> 6 now record where the device protocol and the iOS code differ from the Android original)
> **Source**: Ported from Android `FrameParser.java`, `DataReassembler.java`, `BleEthTransport.java`
> **iOS code**: `KeyCmd/Services/BleEth/` — `FrameParser`, `DataReassembler`,
> `BleEthTransport`, `QueuePipe`, `TransportAdapter`; writes go through
> `KeyCmd/Managers/BLEManager.swift`

This document defines the wire protocol used by the Openterface device to tunnel TCP
traffic over BLE GATT. Where the iOS client deviates from the Android description, the
deviation is called out inline as **iOS**.

---

## 1. Frame Format

All frames are big-endian, 1-byte fields:

```
Offset  Field     Description
------  --------  --------------------------------------------------
0       SYNC1     Fixed: 0x57
1       SYNC2     Fixed: 0xAB
2       ADDR      Target address (unsigned byte). Client always uses 0x00.
3       CMD       Command byte (see Section 2)
4       LEN       Payload length (unsigned byte). Max: 249.
5…4+L   PAYLOAD   0 to 249 bytes
5+L     CHECKSUM  Sum of all preceding bytes, mod 256 (see Section 3)
```

### Constants

| Constant | Value |
|----------|-------|
| `SYNC1` | `0x57` |
| `SYNC2` | `0xAB` |
| `HEADER_LEN` | `5` |
| `MAX_PAYLOAD_LEN` | `249` |
| `MAX_FRAME_LEN` | `255` (5 + 249 + 1) |

### Frame Parser State Machine

The parser uses 7 states to process incoming bytes:

| State | Value | Behavior |
|-------|-------|----------|
| `WAIT_HEAD1` | 0 | Idle, scanning for `0x57` |
| `WAIT_HEAD2` | 1 | Have `0x57`, need `0xAB`. If another `0x57` arrives, restart sync. |
| `WAIT_ADDR` | 2 | Reading address byte |
| `WAIT_CMD` | 3 | Reading command byte |
| `WAIT_LEN` | 4 | Reading length. If `len==0` → `WAIT_CHECKSUM`. If `len>249` → reset to `WAIT_HEAD1`. |
| `WAIT_PAYLOAD` | 5 | Collecting payload bytes into buffer |
| `WAIT_CHECKSUM` | 6 | Verify checksum. On match → emit `ParsedFrame`. Always → `WAIT_HEAD1`. |

**Sync recovery**: If `WAIT_HEAD2` sees another `0x57`, it restarts sync rather than dropping to `WAIT_HEAD1`. This handles the case where the sync bytes themselves are split across BLE notifications.

---

## 2. Command Codes

Commands are asymmetric — client→device uses `0x1x`, device→client uses `0x9x`, plus one unsolicited event:

| Code | Direction | Name | Payload Format |
|------|-----------|------|----------------|
| `0x10` | client → device | `CMD_CONNECT` | `[ip0, ip1, ip2, ip3, port_hi, port_lo]` (6 bytes, IPv4 big-endian) |
| `0x11` | client → device | `CMD_DATA` | 3-byte frag header + chunk data |
| `0x12` | client → device | `CMD_DISCONNECT` | `[connId]` (1 byte) |
| `0x1F` | client → device | `CMD_INFO` | — (empty). **iOS never sends this**; the constant exists for parity with Android |
| `0x90` | device → client | `CMD_CONNECT_RESP` | `[connId, status]` (≥2 bytes) |
| `0x91` | device → client | `CMD_DATA_RESP` | Frag header + data (push) OR `[status]` (ACK) |
| `0x92` | device → client | `CMD_DISCONN_RESP` | `[closedConnId]` |
| `0xD2` | device → client | `CMD_CONN_CLOSED` | `[closedConnId]` — unsolicited close event |
| `0x9F` | device → client | `CMD_INFO_RESP` | — (empty). **iOS only logs it**; no state change is driven by it |

### CONNECT Payload (6 bytes, big-endian)

```
byte[0..3] = IPv4 octets  (e.g., "192.168.1.5" → 0xC0 0xA8 0x01 0x05)
byte[4]    = port >> 8     (high byte)
byte[5]    = port & 0xFF   (low byte)
```

### CONNECT_RESP Payload (≥2 bytes)

```
byte[0] = connId       (unsigned)
byte[1] = status       (0x00 = success; non-zero = failure)
```

### DATA_ACK Detection Heuristic

A `CMD_DATA_RESP` (0x91) frame is treated as an ACK if:
- `payload[0] == 0x00`, OR
- `(payload[0] & 0xF0) == 0xE0` (any status in `0xE0…0xEF`)

Otherwise, the frame is treated as a data push and fed to the reassembler.

---

## 3. Checksum Algorithm

```
checksum = 0
for each byte b in frame[0 .. length-2]:
    checksum += b
checksum_byte = checksum & 0xFF     // low 8 bits of arithmetic sum
```

Equivalently: sum of `SYNC1 + SYNC2 + ADDR + CMD + LEN + payload` bytes, taken mod 256.

**Note**: This is a simple unsigned-byte sum, not CRC. Easy to collide on noise; sync recovery relies on the 2-byte header `0x57 0xAB`.

---

## 4. Fragmentation Protocol

Large payloads are split into multiple `CMD_DATA` frames. Each fragment carries a 3-byte header.

### Fragment Header (3 bytes)

```
Offset  Field   Bit Layout
------  ------  ------------------------------------------------
0       FLAGS   bit 7 = FRAG_MORE (0x80) — more fragments follow
                bit 6 = FRAG_FIRST (0x40) — first fragment of message
                bits 0-3 = total fragment count (masked by 0x0F)
                bits 4-5 unused
1       SEQ     Fragment sequence number, 0-based (unsigned byte)
2       CONNID  Connection ID the fragment belongs to
```

### Constants

| Constant | Value |
|----------|-------|
| `FRAG_HEADER_LEN` | `3` |
| `FRAG_MORE` | `0x80` |
| `FRAG_FIRST` | `0x40` |
| `FRAG_COUNT_MASK` | `0x0F` |
| `MAX_FRAG_DATA` | `246` (249 - 3) |

### Fragmentation Rules (Sender)

- `totalFrags = ceil(dataLen / 246)`
- For each fragment `seq` in `0 .. totalFrags-1`:
  - `flags = (totalFrags & 0x0F)`
  - If `seq == 0`: `flags |= 0x40` (FRAG_FIRST)
  - If `seq < totalFrags - 1`: `flags |= 0x80` (FRAG_MORE)
  - Else: MORE bit is 0 → marks last fragment
- Inter-fragment delay: `Thread.sleep(5)` ms between consecutive fragments (prevents overwhelming firmware BLE receive buffer).

**iOS**: same arithmetic, but a message that fits in one fragment is sent with
`flags = FRAG_FIRST | 0x01` (`0x41`) — an explicit count of 1, not `0x40`. The device
does **not** normalize a received `count = 0` up to 1 the way the iOS receiver does, so
sending `0x40` makes the firmware mis-handle the frame. See `BleEthTransport.sendFragmented`.
Pacing matches Android: `Thread.sleep(0.005)` between fragments, plus a further 10 ms
between 128-byte BLE chunks applied lower down in `BLEManager.sendRawData` — so one
fragment larger than 128 bytes costs several paced writes.

### Reassembly Rules (Receiver)

1. If `FRAG_FIRST` is set → start new reassembly: reset buffer, record `totalFrags`, set `nextSeq = 0`, mark `active = true`, remember the fragment's `connId`.
2. If not `active`, drop the fragment (return null).
3. **iOS only**: if `connId != reassemblyConnId` → skip the fragment and keep reassembling. The device interleaves frames belonging to its other connections.
4. **iOS only**: if `seq != nextSeq` → drop *that fragment* and **keep `active`**. Device ACKs can land inside a message; discarding the whole reassembly proved worse than losing one fragment.
   *(Android reference behavior: out of order discarded the entire message — `active = false`, return null. No selective recovery there either.)*
5. Append `payload[3..]` to buffer, `nextSeq++`.
6. If `FRAG_MORE == 0` (last fragment) → return `ReassembledData(connId, buffer)`, mark `!active`.
7. Otherwise return null (waiting for more fragments).

### Protocol Limits

- **Fragment count field is only 4 bits** (`flags & 0x0F`), so maximum 15 fragments per message → max tunneled payload = 15 × 246 = **3,690 bytes** per fragmented message.
- **Out-of-order fragments are fatal** in the Android reference — the reassembler drops the entire in-progress message and goes idle; there is no NACK / retransmit at this layer. **iOS instead drops only the offending fragment and continues** (rule 4 above), which keeps a session alive but can silently truncate a message: nothing re-requests it.
- **Fragment count value `0` is normalized to `1`** on receive, so a single-fragment message can set count=0 (no MORE, FIRST set). **iOS does this normalization on receive but never emits count=0 on send** — see the sender note above.

---

## 5. Connection Lifecycle

### State Machine (Implicit)

| Condition | Logical State |
|-----------|---------------|
| `connId == -1`, `running == false` | **IDLE / CLOSED** |
| `connect()` in progress, awaiting latch | **CONNECTING** |
| `running == true`, `connId >= 0` | **CONNECTED** |
| `disconnect()` called | **DISCONNECTING** → IDLE |

`isConnected()` returns `running && connId >= 0`.

### Connect Flow

1. Under lock: close any existing pipes, reset `inputPipeClosed=false`, `running=false`, `connId=-1`.
2. Create two `QueuePipe(256)` instances (capacity = 256 queue entries).
3. Start output reader thread — polls outbound pipe and sends via `send()`. Waits for `running && connId >= 0` by sleeping 50 ms in a loop.
4. Build and transmit `CMD_CONNECT` frame via BLE write callback.
5. Create `CountDownLatch(1)` and await `timeoutMs` milliseconds (caller-supplied, typically 20000).
6. On latch timeout → `listener.onError("BLE-Eth CONNECT timed out")`.
7. On latch countdown → check `pendingConnStatus`; if not `0x00` → `listener.onError("BLE-Eth CONNECT failed: status=0x…")`.
8. On success → `connId = pendingConnId`, `running = true`.

### Disconnect Flow

1. Under lock: if `!running && connId < 0 && inputPipeClosed` → return (already closed). Otherwise: `running=false`, snapshot `disconnectConnId = connId`, `connId=-1`, `inputPipeClosed=true`, close both pipes.
2. Interrupt and null out the output reader thread.
3. If there was a valid connId, build and send a `CMD_DISCONNECT` frame with `[connId]`.
4. Notify `listener.onDisconnected()`.

**Note**: Disconnect is half-fire-and-forget — client sends `CMD_DISCONNECT` and immediately tears down local state; it does not wait for `CMD_DISCONN_RESP`. If the device later sends `CMD_DISCONN_RESP` / `CMD_CONN_CLOSED` for a now-stale connId, the code compares against current `connId` (which is already -1) and ignores it.

### Receive-Side Close Events

`CMD_DISCONN_RESP` (0x92) or `CMD_CONN_CLOSED` (0xD2) with `closedConnId == connId` triggers the same teardown (without re-sending DISCONNECT).

---

## 6. QueuePipe — Thread-Safe Byte Pipe

**Purpose**: Replacement for `java.io.PipedInputStream/PipedOutputStream`. The JDK pipe classes track the writing thread and throw `"Write end dead"` if that thread exits — fatal for SSH clients whose handshake runs on a transient connect thread that terminates mid-session.

### Architecture

- Backed by `LinkedBlockingQueue<byte[]>` with configurable capacity (BleEthTransport uses 256).
- `PipeInputStream` (reader) and `PipeOutputStream` (writer) are inner classes.
- Each queue entry is a byte-array chunk. A **zero-length `byte[0]` is the EOF sentinel**.

### Writer Semantics (`PipeOutputStream.write(buf, off, len)`)

- Rejects `len == 0` (so zero-length can only be pushed by `close()` / `signalEndOfStream()`).
- Uses `queue.offer(copy, 1, TimeUnit.SECONDS)` in a loop checking `writerClosed`, to avoid indefinite deadlock if reader vanishes.
- `flush()` is a no-op — queue entries are visible immediately.

### Reader Semantics (`PipeInputStream.read(buf, off, len)`)

- Maintains a `leftover` byte-array + `leftoverPos` for partial consumption of a chunk.
- If leftover exists, drains it first (returns up to `len` bytes).
- Otherwise `queue.take()` (unbounded blocking).
- If dequeued entry is null or `length == 0` → return -1 (EOF).
- Otherwise copy up to `len` bytes, stash remainder as leftover.

### Close Semantics

- `QueuePipe.close()` → sets `closed=true`, pushes EOF sentinel.
- `PipeOutputStream.close()` → sets `writerClosed=true`, pushes EOF sentinel.
- `PipeInputStream.close()` → `queue.clear()` — unblocks writers by discarding buffered data.

### iOS Implementation (`QueuePipe.swift`)

The iOS class keeps the same shape (`writer` / `reader`, `Data?` chunks, `nil` as the EOF
sentinel) but is built on `AsyncStream<Data?>` with
`bufferingPolicy: .bufferingNewest(capacity)`, `capacity` defaulting to 256. Differences
that matter to callers:

| Android reference | iOS | Consequence |
|---|---|---|
| Unbounded-ish `LinkedBlockingQueue`, writer blocks on `offer(…, 1s)` and retries while `!writerClosed` | Bounded stream; when full the **oldest buffered chunk is dropped silently** | A slow reader causes data loss, not back-pressure. Never assumes "write blocks until read" |
| `queue.take()` blocks the reader thread | `await reader.read()` suspends | No thread is parked; reading must happen in a Task |
| Partial chunk consumption via `leftover` + `leftoverPos` | Each `read()` returns one whole chunk | Callers must not assume `read()` respects a requested length |
| `write(len == 0)` rejected explicitly | `write` ignores empty data **and** silently returns once closed | Writes after `close()` vanish without an error |
| Reader close clears the queue to unblock writers | Reader close sets a local `closed` flag; already-yielded elements stay in the stream | `close()` on the read side is not an immediate teardown of buffered payload |

Both `writer.close()` and `QueuePipe.close()` yield the `nil` sentinel and then
`continuation.finish()`, so a pending `read()` resolves to `nil` (EOF) rather than
hanging.

---

## 7. iOS Implementation Notes

### BLEManager Integration

`BLEManager` (singleton, `KeyCmd/Managers/BLEManager.swift`) exposes the two members the
transport needs — both already implemented:

```swift
// Raw data write for the BLE-Eth tunnel
func sendRawData(_ data: Data)

// Raw data receive — one publisher, fed by FFF1 notifications
let rawDataSubject = PassthroughSubject<Data, Never>()
```

The two write paths are deliberately **not** the same mechanism:

| Path | Used by | Write type |
|---|---|---|
| `sendTouchData(_:)` | HID keyboard/mouse reports | FFF2, `.withoutResponse` |
| `sendRawData(_:)` | BLE-Eth frames | FFF2, `.withResponse` for every frame, 128-byte chunks, 10 ms pacing, serialized on a private write queue |

Receiving is routed by characteristic, not by mode: `didUpdateValueFor` publishes **FFF1**
notifications to `rawDataSubject` unconditionally and performs no HID parsing (so the
earlier "verify with firmware which characteristic carries TCP data" question is settled —
FFF1; FFF2 is write-only from the app's side).

Consequences worth knowing:

- There is no `isTerminalMode` flag. While the device is in HID mode nothing subscribes to
  `rawDataSubject`, so incoming bytes are dropped rather than mis-parsed.
- `sendRawData` still computes `isControlFrame` and logs `writeType=…withoutResponse` for
  data frames. That log is stale: `writeType` is a hardcoded `.withResponse` and the value
  never varies. Trust the code, not the debug line.

### Swift Equivalents

| Java | Swift |
|------|-------|
| `LinkedBlockingQueue<byte[]>` | `AsyncStream<Data>` or `DispatchQueue` + array |
| `CountDownLatch` | `DispatchSemaphore` or `CheckedContinuation` |
| `volatile boolean` | `@Atomic` property wrapper or `OSAllocatedUnfairLock` |
| `Thread.sleep(ms)` | `Task.sleep(for: .milliseconds(ms))` in async context — **not** what ships: both the 5 ms fragment pace and the 10 ms chunk pace call `Thread.sleep` on a serial work queue, which parks that queue for the duration |

### Gotchas

1. **LEN field is a single byte**, so protocol ceiling is 249 payload bytes; anything larger is rejected by the parser.
2. **ADDR byte is hardcoded 0x00** in all frames the client builds.
3. **`CMD_DATA_RESP` (0x91) is dual-use** — same command code carries both data-push (multi-byte fragmented payloads) and single-byte ACKs (status `0x00` or `0xE0–0xEF`).
4. **Disconnect is half-fire-and-forget**: client sends `CMD_DISCONNECT` and immediately tears down local state; it does not wait for `CMD_DISCONN_RESP`.
5. **iOS BLE write limitations**: Unlike Android's RxAndroidBle, iOS CoreBluetooth requires careful chunking and pacing to avoid overwhelming the BLE stack.

### Android Alignment (iOS BLEManager Implementation)

The iOS implementation has been aligned with Android's `BluetoothService` behavior for reliable BLE-Eth communication:

#### Write Modes

**Important Discovery:** The device firmware requires BLE-level write acknowledgment (`.withResponse`) for ALL frames — not just control frames. Without BLE-level ACK, the device receives DATA frames and sends BLE-Eth level ACKs (CMD_DATA_RESP), but silently drops the payload instead of forwarding it to TCP. This manifests as: SSH handshake completes, terminal renders server output, but keystrokes never reach the server.

Android differentiates between control and data frames when writing to BLE:

```java
// Android BluetoothService.java
boolean useAcknowledgedWrite = isControlFrame(data);
characteristic.setWriteType(acknowledgedWrite
    ? BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
    : BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
```

**iOS Implementation (corrected):**

```swift
// ALL frames use .withResponse — device firmware requires BLE-level ACK
// before it processes and forwards data to TCP.
// Using .withoutResponse for data frames causes silent data loss post-handshake.
let writeType: CBCharacteristicWriteType = .withResponse
```

**Rationale:** The device firmware processes incoming BLE data only after the BLE write is acknowledged at the link layer. Without acknowledgment, the device's BLE stack accepts the notification but the application layer never sees the data. This affects data frames (CMD_DATA) specifically — control frames already used `.withResponse`. The symptom is asymmetric: server→client works (device initiates BLE notifications), but client→server silently fails after SSH handshake.

#### Chunked Writes with Pacing

Android chunks large writes to 128 bytes with 10ms inter-chunk delays to prevent BLE buffer overflow:

```java
// Android BluetoothService.java
private static final int SAFE_BLE_STREAM_CHUNK = 128;
private static final int BLE_ETH_INTER_CHUNK_DELAY_MS = 10;

while (offset < data.length) {
    int chunkLen = Math.min(SAFE_BLE_STREAM_CHUNK, data.length - offset);
    // ... write chunk ...
    Thread.sleep(BLE_ETH_INTER_CHUNK_DELAY_MS);
}
```

**iOS Implementation:**

```swift
private enum BLEConstants {
    static let safeChunkSize = 128      // bytes per chunk
    static let interChunkDelayMs = 10   // delay between chunks
}

if data.count <= BLEConstants.safeChunkSize {
    // Single write
    performWrite(peripheral: peripheral, characteristic: characteristic, data: data, writeType: writeType)
} else {
    // Chunked write with pacing — all chunks use .withResponse
    var offset = 0
    while offset < data.count {
        let chunkEnd = min(offset + BLEConstants.safeChunkSize, data.count)
        let chunk = data[offset..<chunkEnd]
        performWrite(peripheral: peripheral, characteristic: characteristic, data: Data(chunk), writeType: .withResponse)
        offset = chunkEnd
        if offset < data.count {
            Thread.sleep(forTimeInterval: Double(BLEConstants.interChunkDelayMs) / 1000.0)
        }
    }
}
```

#### Single-Threaded Write Queue

Android uses a single-threaded executor to serialize all BLE-Eth writes:

```java
// Android BluetoothService.java
private final ExecutorService bleEthWriteExecutor = Executors.newSingleThreadExecutor();
```

**iOS Implementation:**

```swift
private let bleEthWriteQueue = DispatchQueue(label: "com.keycmd.bleEth.write", qos: .userInitiated)

// All writes go through this queue
bleEthWriteQueue.async {
    // ... perform write ...
}
```

**Rationale:** BLE writes must be serialized to prevent race conditions and ensure proper ordering, especially when control frames and data frames are interleaved.

#### Control Frame Detection

```swift
private func isControlFrame(data: Data) -> Bool {
    guard data.count > 3 else { return false }  // Frame must have at least header bytes
    let cmd = data[3]  // CMD byte is at offset 3 in the frame
    return cmd == 0x10 ||  // CONNECT
           cmd == 0x12 ||  // DISCONNECT
           cmd == 0x1F     // INFO
}
```

#### MTU Negotiation

Android explicitly requests MTU negotiation to 247 bytes:

```java
// Android BluetoothService.java
private static final int BLE_ETH_TARGET_MTU = 247;
connection.requestMtu(BLE_ETH_TARGET_MTU);
```

**iOS Behavior:** iOS CoreBluetooth handles MTU negotiation automatically. The system negotiates the optimal MTU based on device capabilities and connection parameters. iOS does not provide a direct API to request a specific MTU value like Android does.

The iOS implementation uses 128-byte chunks (conservative) which work reliably across all MTU sizes without explicit negotiation.

#### Summary of Differences

| Aspect | Android | iOS |
|--------|---------|-----|
| Write modes | Acknowledged for control, unacknowledged for data | **All writes use `.withResponse`** — device requires BLE-level ACK before forwarding data to TCP |
| Chunk size | 128 bytes | 128 bytes |
| Inter-chunk delay | 10ms | 10ms |
| Write queue | Single-threaded `ExecutorService` | Serial `DispatchQueue` |
| MTU negotiation | Explicit request to 247 | Automatic (system-managed) |
| Control frame detection | Check CMD byte at index 3 | Same |

These alignment changes ensure consistent, reliable BLE-Eth communication across both platforms, preventing buffer overflows, ensuring proper frame ordering, and optimizing for the characteristics of each platform's BLE stack.

---

## 8. Timeout & Delay Constants

| Constant | Value | Where Used |
|----------|-------|------------|
| `timeoutMs` | parameter; **iOS passes 30000** from `TerminalViewModel.connect` (Android reference used 20000), and `SSHClient` sets the libssh2 session timeout to 30000 ms | `connect()` latch await |
| `100 ms × 50` | poll interval | iOS waits for `transport.isConnected` after `connect()` (Android sleeps 50 ms in its output-reader wait loop) |
| `5 ms` | inter-fragment delay | Pacing between consecutive fragments (`Thread.sleep` on the sender) |
| `10 ms` | inter-chunk delay | Pacing between 128-byte BLE writes in `BLEManager.sendRawData` |
| `256` | queue capacity | `QueuePipe` instances per direction — note iOS `.bufferingNewest(256)` drops the oldest chunk on overflow |
| `1 second` | write backoff | `PipeOutputStream.write` re-check `writerClosed` (Android only; iOS yields into the stream and never blocks) |
| `246` | read buffer | Max read per outbound chunk (= `MAX_FRAG_DATA`). Limits each `transport.send()` to a single BLE-Eth fragment. The original Android spec uses 4096 which produces multi-fragment DATA frames, but the device firmware silently drops multi-fragment frames for client→server direction. |

---

## 9. Testing

### Unit Test Fixtures

Live in `KeyCmdTests/` and run as unit tests of the `KeyCmd` scheme (the separate
`KeyCmdUITests` scheme covers UI only):

1. **`FrameParserTests`** — feed raw bytes
   `[0x57, 0xAB, 0x00, 0x10, 0x06, 0xC0, 0xA8, 0x01, 0x05, 0x00, 0x16, <checksum>]`,
   assert `addr=0, cmd=0x10, payload=[0xC0, 0xA8, 0x01, 0x05, 0x00, 0x16]`; sync recovery
   and checksum rejection are covered in the same file.
2. **`DataReassemblerTests`** — `testSingleFragment`, `testMultipleFragments`
   (FIRST+MORE then last) and `testOutOfOrderFragment` behavior.
3. **Out-of-order fragments** — feed FIRST (seq=0), then seq=2 skipping seq=1. What iOS
   actually guarantees is that **no message is emitted**; the in-progress reassembly stays
   `active` rather than being discarded as the Android reference does. The test asserts
   `results.count == 0` and its inline comment still says "should discard entire
   reassembly" — that wording describes Android, not the shipped iOS behavior described in
   [Section 4](#reassembly-rules-receiver).
4. **`QueuePipeTests`** — chunk hand-off, `nil` EOF sentinel, post-close writes vanishing.
5. **`BleEthTransportTests`** — encode the [Section 7](#7-ios-implementation-notes) rules,
   in particular that every BLE write uses `.withResponse`.
6. **`BLEManagerTests`** — scan filtering and characteristic discovery.

### Manual / hardware

BLE cannot be exercised on the Simulator. End-to-end verification is: pair with the
device → open Terminal → connect to a known SSH host → confirm handshake, rendering,
keystroke delivery to the server, and behavior under a large `cat` (throughput plus the
246-byte single-fragment limit).
