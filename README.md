# Mygration

**NameDrop for your whole Mac.** Bring two Macs together and your *setup*
migrates — apps, packages, projects, secrets, and your AI agent's memory.
Encrypted, verified, native. It moves your **setup**, not your files.

🎵 *Soundtrack: [Torin Frost × Lauren Santi — Ch.I Mygration (Bye Bye)](https://www.youtube.com/watch?v=5AM7aZ8YBdg)*

Born from a real Intel iMac → Apple Silicon MacBook migration done entirely
without Migration Assistant — because on an architecture change, copying bytes
copies the wrong bytes. Mygration captures what your machine *is* (declaratively)
and rebuilds it natively on the target, then keeps your Macs converged nightly.
Every design rule in [docs/field-notes.md](docs/field-notes.md) was paid for
with a real 2am failure.

## The three channels

| What | Travels by | Why |
|---|---|---|
| Code | git remotes; nightly ff-only pulls + `wip/<machine>` snapshot branches | git *is* the sync protocol for code — never file-sync a live repo |
| Environment | manifests in YOUR private state repo (Brewfile, repos, dotfiles, keychain item *names*) | declarative; rebuilds natively on any architecture |
| Secrets & agent state | `secrets.tar.gz.enc` (AES-256, passphrase) | never plaintext in git; tokens re-enter the Keychain per machine |

Never synced: `node_modules`, build artifacts, caches (arch-specific —
regenerate), SSH keys (new key per machine), OAuth logins (re-auth per machine).

## Setup

Your manifests describe your machine — they're personal. So this repo is the
**engine**; your state lives in a **private** copy:

```bash
gh repo clone YOURUSER/mygration ~/Sites/migration   # your PRIVATE copy of this repo
cd ~/Sites/migration
cp mygration.conf.example mygration.conf              # edit: user, source host, paths
./capture.sh secrets                                  # on the source Mac
git add -A && git commit -m snapshot && git push
```

New machine in five lines:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)" && brew install gh
gh auth login
gh repo clone YOURUSER/mygration ~/Sites/migration
cd ~/Sites/migration && ./wizard.sh
```

## The scripts

| Script | Run on | Does |
|---|---|---|
| `capture.sh` | source | Snapshot reality → manifests; `secrets` arg encrypts env files + agent state into the bundle |
| `audit.sh` | source | Discover the long tail: apps vs casks, launch agents, docker volumes, hidden/secret configs → decision lists |
| `bootstrap.sh` | target | Converge: brew bundle (adopts pre-existing apps), dotfiles (backed up), clone repos (HTTPS until your SSH key exists), keychain prompts, bundle decrypt, agent-state restore with path re-keying |
| `wizard.sh` | target | Guided sign-ins; every step **verifies itself** — `[r]` runs steps for you |
| `verify.sh` | both | ~80 behavioral probes from manifests + live scans. **Done = empty diff between machines** |
| `sync.sh` + `install-sync.sh` | daily driver | Nightly launchd loop: capture → commit → converge; wip-snapshots protect uncommitted work; ntfy/notification report |
| `pull-claude.sh` | target | Claude Code transcript sync over Tailscale/LAN — walks you through opening the SSH gate and **verifies you closed it** |
| `profiles/cswap.sh` | any | Claude Code profile hot-swap (work/personal isolation via `CLAUDE_CONFIG_DIR`) |

## AI agent state

Your agent's accumulated context — per-project memory, skills, plugins — is
captured into the encrypted bundle and restored with project keys re-mapped to
the new machine's paths. MCP configs are treated as credentials (encrypted
lane only, reviewed by hand). Session transcripts move only machine-to-machine
(`pull-claude.sh`), never through a repo.

## Security model

- Secrets exist in exactly two forms: macOS **Keychain** or the **AES-256
  bundle** (passphrase in your password manager). Nothing plaintext in git —
  and `capture.sh` scans for a dozen token dialects before anything is copied.
- Your private state repo is executable trust: 2FA, no collaborators.
- Any gate a script asks you to open (SSH), it verifies you closed.
- Delete the bundle from your repo history once both machines are converged —
  the courier dies after delivery.

## Roadmap

`specs/` holds where this is going: proximity pairing (Bonjour/AWDL, PIN
ceremony), the pick-and-choose diff UI, and a menu bar app — the full
NameDrop-for-Macs experience. The CLI you're holding is that product's engine,
proven in the field first.
