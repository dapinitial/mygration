#!/bin/bash
# pull-claude.sh — run on the TARGET Mac. Pulls Claude Code session transcripts
# and command history from a source Mac over Tailscale, wizard-style: it walks
# you through opening the SSH gate, verifies, syncs, then verifies you CLOSED
# the gate — it won't declare success while the door is still open.
#   ./pull-claude.sh [source-tailscale-name]   (default: $SOURCE_HOST)
set -uo pipefail
# load user config (see mygration.conf.example)
MYG_CONF="$(cd "$(dirname "$0")" && pwd)/mygration.conf"
[ -f "$MYG_CONF" ] && . "$MYG_CONF"
MYG_USER="${MYG_USER:-$(whoami)}"
SITES_DIR="${SITES_DIR:-$HOME/Sites}"
SOURCE_HOST="${SOURCE_HOST:-old-mac}"
SOURCE_HOME="${SOURCE_HOME:-/Users/$MYG_USER}"

SRC="${1:-$SOURCE_HOST}"
TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
[ -x "$TS" ] || TS="tailscale"

echo "🧠 Pulling Claude agent history from $SRC"

# tailnet lookup is only a hint — .local names and LAN IPs are equally valid;
# the real test is whether the SSH gate answers (below)
if command -v "$TS" >/dev/null 2>&1 && "$TS" status 2>/dev/null | grep -qi "$SRC"; then
  echo "  ⓘ found '$SRC' on your tailnet"
else
  echo "  ⓘ '$SRC' isn't a tailnet peer name — treating it as a direct host/IP (.local or LAN)"
fi

gate_open() { nc -z -w 3 "$SRC" 22 >/dev/null 2>&1; }

if ! gate_open; then
  echo "── The SSH gate on $SRC is closed (good default). To open it temporarily:"
  echo "   On $SRC: System Settings → General → Sharing → Remote Login → ON"
  while ! gate_open; do
    printf "   [enter]=I turned it on, re-check   [q]uit → "
    read -r ans </dev/tty; [ "$ans" = "q" ] && exit 0
  done
fi
echo "  ✓ gate open — syncing (additive, nothing on this Mac is deleted)"

# one rsync, one ssh session, one password; plain flags (macOS ships openrsync,
# which rejects modern --info options)
if rsync -av --progress "$MYG_USER@$SRC:.claude/projects" "$MYG_USER@$SRC:.claude/history.jsonl" "$HOME/.claude/"; then
  echo "  ✓ transcripts + per-project memory + command history"
else
  echo "  ✗ rsync failed — gate stays open; fix and re-run"; exit 1
fi

n=$(find "$HOME/.claude/projects" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
echo "  ✓ $n session files now on this Mac"

echo "── Now CLOSE the gate: on $SRC, Remote Login → OFF"
while gate_open; do
  printf "   [enter]=I turned it off, verify → "
  read -r ans </dev/tty
done
echo "  ✓ gate verified closed"
echo "✅ Done — full conversation history is local. Try:  claude --resume"
