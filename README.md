<div align="center">

# 🌌 Mygration

### NameDrop for your whole Mac.

**Bring two Macs together and your *setup* migrates** — repos, dev tools, secrets,
and your AI agent's memory. Encrypted, verified, native. It moves your **setup**,
not your files.

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-0a84ff)]()
[![Swift](https://img.shields.io/badge/Swift-5.10-f05138)]()
[![License](https://img.shields.io/badge/license-MIT-4fd89a)]()
[![Tests](https://img.shields.io/badge/tests-10%20passing-37d4cf)]()

🎵 *Soundtrack: [Torin Frost × Lauren Santi — Ch.I Mygration (Bye Bye)](https://www.youtube.com/watch?v=5AM7aZ8YBdg)*

</div>

---

> Born from a real Intel iMac → Apple Silicon MacBook migration done **without
> Migration Assistant** — because on an architecture change, copying bytes copies
> the *wrong* bytes. Mygration captures what your machine *is* (declaratively) and
> rebuilds it natively on the target. Every design rule in
> [`docs/field-notes.md`](docs/field-notes.md) was paid for with a real 2am failure.

## Why not Migration Assistant?

|  | Migration Assistant | **Mygration** |
|---|---|---|
| Intel → Apple Silicon | copies x86 binaries, runs under Rosetta | **rebuilds native** (arm64) |
| Homebrew | drags `/usr/local` cruft along | **`brew bundle`, clean** |
| What moves | *everything*, indiscriminately | **you pick, à la carte** |
| AI agent memory | no concept of it | **transfers Claude/Gemini/… state** |
| "Did it work?" | hope | **~80 behavioral probes; done = empty diff** |
| Verdict | moves your *files* | moves your ***setup*** |

## How it works

```
        ┌── iMac (x86_64) ──┐         ┌── MacBook (arm64) ─┐
        │  discover ledger  │  ◀PIN▶  │  discover ledger   │
        │  advertise (AWDL) │═════════│  find · pair · PIN │
        └───────────────────┘  TLS    └────────────────────┘
                 source  ──── real ledger ────▶  target
                                                   │
                     à-la-carte plan  ◀────────────┘
                 repos · agents · services · env · keychain · brew · beyond-brew
                                                   │
        clone repos · brew bundle · stream secrets · transfer AI memory · verify
```

1. **Open the app on both Macs.** One shows a PIN; type it on the other — the
   iCloud-device-approval ceremony, over an AWDL peer-to-peer channel.
2. **They exchange real ledgers** across the encrypted (TLS-PSK) connection.
3. **Pick what moves** — a checklist with a *how-it-travels* badge on every item.
4. **Migrate.** Repos clone, Homebrew installs native, env-file secrets stream
   over the channel, AI agent memory transfers (curated — never the transcripts).
5. **Verify.** Behavioral probes confirm the new Mac *behaves* like the old one.

## What it discovers

Seven catalogs, each a living constellation in the native 3D **`Visualize this Mac`** view:

| Category | What travels · how |
|---|---|
| **Repositories** | multi-root scan (`~/Sites`, `~/Code`, `~/Repos`, …) → `git clone` |
| **AI agents** | Claude · Codex · Gemini · Ollama · Copilot · Cursor · Qwen · Grok · Kimi · Llama · Amazon Q — memory transfers, models re-pull, secrets stay |
| **Local services** | Apache · nginx · PHP · MySQL · Postgres · Redis · Valet — config travels, DBs dump, daemons reinstall |
| **Env files** | `.env` / `.envrc` → streamed over the encrypted channel |
| **Keychain** | tokens re-entered per machine (never copied — by design) |
| **Homebrew** | formulae + casks → `brew bundle`, native |
| **Beyond Homebrew** | curl-installed tools + manual apps, with exact reinstall commands |

## Screenshots

> _Drop images in `docs/img/`. Capture from the app with ⌘⇧4._

| The ceremony | The plan | The constellation |
|---|---|---|
| ![pairing](docs/img/pairing.png) | ![plan](docs/img/plan.png) | ![graph](docs/img/graph.png) |

## Architecture

- **`MygrationCore`** — the engine (Swift package, open): Ledger, catalogs
  (agents/services/extras), pairing (Bonjour + AWDL + PIN→TLS-PSK), file/tree
  transfer, executor. Fully testable, no UI.
- **`app/`** — the SwiftUI app (Xcode project): MenuBarExtra, the pairing
  ceremony with a real Metal NameDrop ripple, the à-la-carte plan, and the
  SceneKit 3D ledger constellation with HDR bloom.
- **`legacy/`** *(coming)* — the field-proven bash kit kept as the golden
  reference; CI diffs it against the Swift engine.

```bash
git clone https://github.com/YOURUSER/mygration && cd mygration
swift test                        # the engine + 10 tests
cd app && xcodegen generate && open Mygration.xcodeproj   # ⌘R to run the app
```

## Security

- Secrets live in exactly two forms: **macOS Keychain** or a **TLS-PSK channel**
  keyed by the PIN. Never plaintext on disk-in-transit, never a cloud.
- The source serves **only files it advertised** — a peer can't request `~/.ssh`.
- Agent transfer excludes session transcripts and caches (they can hold pasted
  secrets); it moves the *curated brain*, not the logs.
- Distributed as a **notarized Developer-ID app** — never the App Store (its
  sandbox forbids running `git`/`brew` and touching your dotfiles). See
  [`app/release.sh`](app/release.sh).

## Roadmap

`specs/` holds where this is going: the full proximity-pairing bubble UX, an
AI-guided discovery conversation (Claude narrating your migration), and the
menu-bar product. The CLI engine you're holding is that product's core, proven
in the field first.

<div align="center">

**Migration Assistant moves your files. Mygration moves your setup.** 🌌

</div>
