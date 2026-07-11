# Spec: Mygration — the two-Mac Quick Start UX

**One-line pitch:** put two Macs near each other and they set each other up —
like iPhone Quick Start, but it moves your *setup*, not your files.

## The flow (and what tonight's CLI proved for each step)

1. **Install Mygration on both Macs.** Menu bar app. (CLI proved: the engine is
   ~8 small scripts; the app is a shell around them.)

2. **Proximity pairing.** Devices discover each other via Bonjour + AWDL
   peer-to-peer Wi-Fi (Network.framework `includePeerToPeer` — the sanctioned
   AirDrop radio path). One Mac displays a 6-digit PIN, the other enters it
   (short-authentication-string verification of the E2E-encrypted channel —
   the Quick Start / Bluetooth-pairing ceremony users already trust). Each Mac
   asks for its local login password before touching Keychain-adjacent data.

3. **Both sides self-discover.** capture + audit run on each machine → a ledger
   each: apps (source-classified), packages, repos (+ dirty/unpushed state),
   configs, secrets-by-name, agent state, launch agents, local DB volumes,
   loose files. (Proved: audit.sh found things the owner forgot existed.)

4. **The diff, translated.** Ledgers cross the channel; the diff engine renders
   a *plan*, arch-aware: "9 apps reinstall natively via Homebrew (you're
   Apple Silicon; your x86 copies won't be copied)" · "39 CLI packages, arm64"
   · "node_modules/builds: regenerated, never transferred" · "2 repos have
   work trapped on the old Mac" · "3 Docker volumes need dumps". (Proved:
   Brewfile rebuild, adopt-mode, wip-snapshots, Supabase dumps.)

5. **Pick and choose.** The plan is a checklist grouped by category — Apps,
   Projects, Secrets & keys, AI agent state, Settings, Big files — every row
   showing HOW it travels (native reinstall / git / encrypted direct transfer /
   re-auth) and defaulting to the safe choice. This is DECISIONS.md as UI.
   Nothing moves without a checkbox. (Proved: the checkbox file worked; users
   change their minds mid-flight — adopt-don't-reinstall came from live use.)

6. **Guided transfer with instructions.** Config + secrets + agent memory move
   directly over the encrypted channel (never a cloud). Apps install natively.
   Steps needing a human (sign into iCloud/Tailscale/GitHub, paste a token,
   grant App Management to Homebrew) appear as wizard cards that EXPLAIN the
   upcoming macOS permission dialog before it fires, offer "do it for me"
   where possible, and verify completion themselves — no honor system.
   (Proved: wizard.sh, [r]un option, ruby/App-Management confusion → cards
   must pre-explain OS prompts.)

7. **The exam.** A behavioral probe suite runs on the new Mac and diffs against
   the old one's baseline: "your new Mac behaves like your old one — 76/76"
   or a short list of red items, each with a fix action. Done = empty diff,
   not "transfer complete". (Proved: verify.sh caught every real gap tonight.)

8. **The closing ceremony.** Every door opened along the way (SSH, permissions,
   temporary keys) is re-checked CLOSED before Mygration declares success.
   (Proved: pull-claude.sh's gate pattern.)

9. **The upsell moment, earned:** "Keep these Macs in sync nightly?" → the
   convergence loop, morning phone report. Migration is the first diff; sync
   is the same diff, scheduled. (Proved: sync.sh + launchd.)

## Trust & safety invariants
- E2E encrypted, peer-to-peer; secrets never touch a server, ever.
- Consent is per-item; safe defaults; nothing implicit.
- Old Mac is never modified (read-only source) except gates the user opens —
  and those are verified shut.
- Arch/provenance translation is explicit in the UI, never silent (users fear
  the Intel→Silicon move; showing the translation IS the trust builder).
- The instructions layer is the product: every macOS permission dialog is
  explained BEFORE it appears (App Management/"ruby", Full Disk Access,
  Accessibility) — surprise dialogs are where users bail or misclick.

## Open UX questions
- Remote pair (no proximity) via relay/tailnet for the "shipping a Mac to
  a new hire" case?
- Multi-Mac (N>2): pick a "golden" source or merge ledgers?
- Post-migration decommission checklist for the old Mac as a first-class screen
  (trapped work, archives, transcripts, deauthorizations)?
