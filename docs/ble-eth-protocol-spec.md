# BLE-Eth Protocol Specification

> **Version**: 1.0
> **Last updated**: 2026-06-20
> **Source**: Ported from Android `FrameParser.java`, `DataReassembler.java`, `BleEthTransport.java`

This document defines the wire protocol used by the Openterface KeyMod device to tunnel TCP traffic over BLE GATT. The iOS implementation must conform exactly to this spec.

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
| `0x1F` | client → device | `CMD_INFO` | — (empty) |
| `0x90` | device → client | `CMD_CONNECT_RESP` | `[connId, status]` (≥2 bytes) |
| `0x91` | device → client | `CMD_DATA_RESP` | Frag header + data (push) OR `[status]` (ACK) |
| `0x92` | device → client | `CMD_DISCONN_RESP` | `[closedConnId]` |
| `0xD2` | device → client | `CMD_CONN_CLOSED` | `[closedConnId]` — unsolicited close event |
| `0x9F` | device → client | `CMD_INFO_RESP` | — (empty) |

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

### Reassembly Rules (Receiver)

1. If `FRAG_FIRST` is set → start new reassembly: reset buffer, record `totalFrags`, set `nextSeq = 0`, mark `active = true`.
2. If not `active`, drop the fragment (return null).
3. If `seq != nextSeq` → out of order → discard entire reassembly (`active = false`, return null). **No selective recovery.**
4. Append `payload[3..]` to buffer, `nextSeq++`.
5. If `FRAG_MORE == 0` (last fragment) → return `ReassembledData(connId, buffer)`, mark `!active`.
6. Otherwise return null (waiting for more fragments).

### Protocol Limits

- **Fragment count field is only 4 bits** (`flags & 0x0F`), so maximum 15 fragments per message → max tunneled payload = 15 × 246 = **3,690 bytes** per fragmented message.
- **Out-of-order fragments are fatal** — the reassembler drops the entire in-progress message and goes idle; there is no NACK / retransmit at this layer.
- **Fragment count value `0` is normalized to `1`** on receive, so a single-fragment message can set count=0 (no MORE, FIRST set).

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

---

## 7. iOS Implementation Notes

### BLEManager Integration

Extend `BLEManager` (existing singleton) with:

```swift
// Raw data write (mirrors sendTouchData but for arbitrary bytes)
func sendRawData(_ data: Data)

// Raw data receive (bypasses HID parsing)
let rawDataSubject = PassthroughSubject<Data, Never>()
```

The existing `sendTouchData(data: Data)` writes to FFF2 characteristic `.withoutResponse`. `sendRawData` uses the same mechanism but accepts arbitrary payloads.

When BLE notifications arrive from FFF1 (or whichever characteristic the device uses for TCP data — verify with firmware), publish the raw bytes to `rawDataSubject` instead of parsing them as HID reports.

### Swift Equivalents

| Java | Swift |
|------|-------|
| `LinkedBlockingQueue<byte[]>` | `AsyncStream<Data>` or `DispatchQueue` + array |
| `CountDownLatch` | `DispatchSemaphore` or `CheckedContinuation` |
| `volatile boolean` | `@Atomic` property wrapper or `OSAllocatedUnfairLock` |
| `Thread.sleep(ms)` | `Task.sleep(for: .milliseconds(ms))` in async context |

### Gotchas

1. **LEN field is a single byte**, so protocol ceiling is 249 payload bytes; anything larger is rejected by the parser.
2. **ADDR byte is hardcoded 0x00** in all frames the client builds.
3. **`CMD_DATA_RESP` (0x91) is dual-use** — same command code carries both data-push (multi-byte fragmented payloads) and single-byte ACKs (status `0x00` or `0xE0–0xEF`).
4. **Disconnect is half-fire-and-forget**: client sends `CMD_DISCONNECT` and immediately tears down local state; it does not wait for `CMD_DISCONN_RESP`.

---

## 8. Timeout & Delay Constants

| Constant | Value | Where Used |
|----------|-------|------------|
| `timeoutMs` | parameter (typically 20000) | `connect()` latch await |
| `50 ms` | sleep interval | Output reader wait-for-tunnel loop |
| `5 ms` | inter-fragment delay | Pacing between consecutive fragments |
| `256` | queue capacity | `QueuePipe` instances per direction |
| `1 second` | write backoff | `PipeOutputStream.write` re-check `writerClosed` |
| `4096` | read buffer | Max read per outbound chunk |

---

## 9. Testing

### Unit Test Fixtures

1. **FrameParser**: Feed raw bytes `[0x57, 0xAB, 0x00, 0x10, 0x06, 0xC0, 0xA8, 0x01, 0x05, 0x00, 0x16, <checksum>]`, assert parsed frame has `addr=0, cmd=0x10, payload=[0xC0, 0xA8, 0x01, 0x05, 0x00, 0x16]`.
2. **DataReassembler**: Feed two fragments (FIRST+MORE, then last), assert reassembled data matches original.
3. **Out-of-order fragments**: Feed FIRST, then seq=2 (skipping seq=1), assert reassembly is discarded.
