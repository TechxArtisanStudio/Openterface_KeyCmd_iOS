# Documentation Index

Two documents describe the code as it stands today. Everything else in this directory is
an archived session record, kept for history and explicitly marked.

Each current doc carries a `Version` / `Last updated` block at the top. If that date is
older than the module you are changing, verify against the source before trusting it.

---

## Current

| Document | Covers | Last audited |
|---|---|---|
| [terminal-architecture.md](terminal-architecture.md) | The Terminal mode end to end: `KeyCmd/Services/BleEth` + `KeyCmd/Services/SSH`, `KeyCmd/View/Terminal/`, SwiftTerm integration, libssh2 session settings, key mappings, credential storage, and a list of known gaps | 2026-11-03 |
| [ble-eth-protocol-spec.md](ble-eth-protocol-spec.md) | The wire protocol the device speaks over GATT: frame format, command codes, checksum, fragmentation/reassembly, connection lifecycle, QueuePipe semantics, and every point where the iOS client deliberately differs from the Android original | 2026-11-03 |

These two overlap on purpose — the architecture doc is "how the app is put together", the
protocol doc is "what goes on the wire". Where they disagree, the protocol spec wins on
frame details and the architecture doc wins on app structure.

---

## Archived

Session records from earlier phases of the project. They are **not** maintained, and some
statements in them are actively false. Each file opens with a banner listing what changed;
read the banner before anything else.

| Document | Was | Why it is wrong now |
|---|---|---|
| [archive/todo.md](archive/todo.md) | Android feature-parity checklist for the keyboard (2026-04) | All 8 unchecked items shipped, including the "stretch goal" split keyboard. It also proposed a `target_os` UserDefaults key that does not exist — the value lives in `AISettings.targetOS` |
| [archive/test_report.md](archive/test_report.md) | Test report for that keyboard work (2026-04-28) | Cites `KeyboardMouseView.swift`, since split into `BasicKeyboardMouseView` / `ProKeyboardMouseView`, plus several APIs that no longer exist |
| [archive/implementation-summary.md](archive/implementation-summary.md) | First-pass terminal build report | Every path uses `KeyMod/`, dependency setup it calls "TODO" is done, and the TCP-proxy bridge it describes was replaced by `POSIXSocketBridge` |
| [archive/terminal-feature-plan.md](archive/terminal-feature-plan.md) | The original terminal roadmap | Phases it marks unfinished are shipped; the planned NMSSH / SwiftUI-Canvas / bundled-font choices were all replaced. Its `UIBackgroundModes` item, open when this was written, was added on 2026-11-03 |

---

## Not documentation

Three other places hold Markdown that looks like docs but is not:

- `KeyCmd/Prompts/*.md` — loaded into the app bundle as LLM prompt resources, read at
  runtime by `AIConfigManager`. Editing one changes app behavior.
- `KeyCmd/Openterface_Core/README.md` — belongs to the [Openterface_Core submodule](https://github.com/TechxArtisanStudio/Openterface_Core), describing it in its own context; do not edit it from this repo.
- `README.zh-CN.md` — **referenced nowhere today**. The root README previously linked it
  and the file never existed; the link was removed 2026-11-03. If you want a Chinese
  translation, add the file and restore the link on line 3 of the root README.

## Writing a doc here

English, one `Version` / `Last updated` header block, cite code by repo-relative path and
symbol name rather than line number, and note where iOS diverges from Android — that
divergence is what most readers are actually looking for.
