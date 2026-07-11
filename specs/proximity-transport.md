# Spec: Proximity transport — the NameDrop moment, no Tailscale required

**The scene:** two (or more) Macs in the same room. Mygration is open on both.
They find each other, a pairing bubble blooms, a PIN confirms, and setup flows
between them — contacts-via-NameDrop, but for a machine's entire soul.

## Can this work WITHOUT Tailscale? Yes — proximity needs no overlay network.

| Layer | Technology | Notes |
|---|---|---|
| Discovery | **Bonjour** (`NWBrowser`, `_mygration._tcp`) on LAN; **Bluetooth LE advertising** when no shared network | BLE covers the "brand-new Mac, no Wi-Fi configured yet" case |
| "Near" detection | **BLE RSSI ranging** (signal strength ≈ same-room) | Macs lack the U1/UWB chip that gives iPhones NameDrop's precise "facing" detection — same-room is our honest fidelity; the bubble animates on discovery, not on touch |
| Transfer channel | **AWDL peer-to-peer Wi-Fi** — `NWConnection` with `includePeerToPeer = true` (the sanctioned AirDrop radio path; no router, no infrastructure needed) | Falls back to plain LAN TCP when both are on the same network (faster for bulk) |
| Modern option | **Wi-Fi Aware** (Apple opened third-party support in the '26 OS cycle) | Standards-based AWDL successor; adopt when the deployment floor allows |
| Trust | TLS on the channel + **6-digit SAS/PIN ceremony** (displayed on one, entered on the other) + local login password per side before Keychain-adjacent reads | Identical trust choreography to Quick Start / Bluetooth pairing |
| Remote fallback | Tailscale (or any reachable SSH) — the CLI's current lane | Only needed when machines are NOT proximate: shipped laptop, remote office. Proximity mode never touches it |

## Multi-device (N Macs)

Discovery yields a *constellation*, not a pair: every Mygration instance
advertises; the UI shows all nearby machines as bubbles. The user picks a
**source** (or "golden") machine; each target pairs with it independently
(star topology — same PIN ceremony per pair). Ledger diffs are per-pair, so
three Macs = three independent plans; the source is always read-only.

## The bubble (the sexy part, specified soberly)

- Idle: menu bar icon pulses when a peer is discovered.
- Approach: peer appears as a named bubble (hostname + arch badge: "Intel" /
  "Apple Silicon") that grows with BLE proximity — honest physics, no fake UWB.
- Pair: bubbles touch → PIN sheet on both screens → on success, the bubbles
  merge into a channel with a flowing-particles animation during transfer.
- Every transferred category ticks visibly (apps → packages → projects →
  memory → settings), with the verify exam as the final glow.

## What proximity mode does NOT change

The engine is identical to the CLI's: ledger → translated diff → pick-and-
choose plan → guided transfer → probe exam → gates verified shut. Proximity
replaces only the *transport and pairing* (SSH/Tailscale/passwords → AWDL/PIN).
Everything in `docs/field-notes.md` still applies verbatim.

## Build order

1. CLI keeps SSH/Tailscale (works today, proven).
2. `mygrationd` — a tiny Bonjour+TLS daemon both Macs run; CLI gains
   `./pull-claude.sh --near` (no SSH, no gates to forget — the daemon IS the
   scoped gate, open only while the app runs).
3. Menu bar app wraps the daemon with the bubble UX.
4. BLE discovery/ranging + Wi-Fi Aware as polish.
