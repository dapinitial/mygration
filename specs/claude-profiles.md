# Spec: Claude Code profile hot-swap ("cswap")

## Problem
People run multiple Claude identities on one machine — a corporate/gatewayed
Claude (enterprise base URL, proxy, managed settings, compliance rules) and one
or more personal accounts. Today they share one `~/.claude`, so memory, MCP
servers, and history bleed across contexts. Work context leaking into a personal
sync bundle (or vice versa) is a compliance problem, not just clutter.

## Core mechanism
Claude Code honors `CLAUDE_CONFIG_DIR`. A **profile** is:

```
~/.claude-profiles/<name>/
  config/          ← becomes CLAUDE_CONFIG_DIR (settings, memory, skills, projects…)
  env              ← sourced on activation: ANTHROPIC_BASE_URL, proxy, model,
                     API key via keychain lookup (never plaintext)
  policy.json      ← sync policy: does this profile enter the migration/sync
                     bundle? (work: never; personal: yes)
```

The default `~/.claude` is migrated to become profile `personal`.

## Switching surfaces (in build order)
1. **CLI (`cswap`)** — `cswap work`, `cswap personal`, `cswap ls`, `cswap which`.
   A shell function: exports CLAUDE_CONFIG_DIR + sources the profile env for the
   current shell. Ships in this repo now.
2. **direnv (auto-switch by directory)** — a project's `.envrc` pins its profile:
   `export CLAUDE_CONFIG_DIR=$HOME/.claude-profiles/work/config` + env. cd in →
   work identity; cd out → gone. Zero-thought correctness; matches the existing
   keychain-backed .envrc pattern.
3. **Menu bar app** — shows active profile (per focused terminal is impossible;
   shows default + per-project pins), one-click default toggle, profile badge
   color (work = red), "new profile" wizard. This is the productized layer.

## Sharing model
- **Isolated per profile:** memory, projects/history, MCP registry, settings,
  credentials. (The whole point.)
- **Optionally shared via symlink:** `skills/`, `agents/` — personal tooling you
  want everywhere; a profile opts in: `config/skills -> ../../shared/skills`.
- **Never shared:** work profile content never enters the personal sync/migration
  bundle. `capture.sh` reads each profile's `policy.json` and skips `sync: false`
  profiles entirely.

## Keychain & auth
- Personal profiles: normal OAuth (Keychain). Note: Keychain entry naming vs
  CLAUDE_CONFIG_DIR isolation must be verified empirically; if entries collide
  across two OAuth profiles, fall back to `apiKeyHelper` per profile.
- Gateway/work profiles: env-based (`ANTHROPIC_BASE_URL`, key via
  `security find-generic-password`), no OAuth — no collision.

## Product packaging (decision)
Same app, not a separate one. Profile management and machine sync are the same
discipline — agent-state as managed, lane-classified data — and share the engine
(ledger, secrecy rules, translation/re-keying). The menu bar profile switcher is
the FIRST GUI surface of the product: small, viral, immediately useful, and it
onboards users into the agent-state model that sync/migration then monetizes.
Framework: Tauri is acceptable (cross-platform; Claude Code runs on Linux too),
but Keychain + launchd + Endpoint-Security integrations argue native SwiftUI for
the Mac app; revisit at build time. CLI + direnv layers are product-grade on
their own and ship today.

## Migration/sync interaction
- Profiles are themselves ledger entries: the diff engine treats each profile as
  a unit ("MacBook is missing profile `work`").
- Bootstrap restores profiles honoring policy.json; wizard gains a per-profile
  auth step ("sign into profile personal", "paste gateway key for work").
