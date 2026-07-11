#!/bin/bash
# sync.sh — the nightly (or hourly) convergence loop. Safe by construction:
#   • code: fetch always; ff-only pull on CLEAN trees; dirty trees snapshot to
#     wip/<machine> on the remote — uncommitted work is never stranded or touched
#   • environment: capture.sh + commit/push this repo, pull + converge the rest
#   • report: one summary via ntfy (topic in sync.config) or macOS notification
set -uo pipefail
# load user config (see mygration.conf.example)
MYG_CONF="$(cd "$(dirname "$0")" && pwd)/mygration.conf"
[ -f "$MYG_CONF" ] && . "$MYG_CONF"
MYG_USER="${MYG_USER:-$(whoami)}"
SITES_DIR="${SITES_DIR:-$HOME/Sites}"
SOURCE_HOST="${SOURCE_HOST:-old-mac}"
SOURCE_HOME="${SOURCE_HOME:-/Users/$MYG_USER}"
cd "$(dirname "$0")"

HOST=$(hostname -s)
SITES="$SITES_DIR"
REPORT=()
note() { REPORT+=("$1"); }

# --- 1. environment: capture, commit, pull, converge -------------------------
./capture.sh >/dev/null 2>&1 || note "⚠️ capture.sh failed"
if [ -d .git ]; then
  git add -A >/dev/null 2>&1
  git diff --cached --quiet || { git commit -qm "sync: $HOST $(date +%F)"; note "env: snapshot committed"; }
  git pull --rebase -q 2>/dev/null || note "⚠️ migration repo pull conflict — resolve by hand"
  git push -q 2>/dev/null || note "⚠️ migration repo push failed (no remote?)"
  # converge what's safe to converge automatically
  brew bundle check --file=Brewfile >/dev/null 2>&1 || {
    added=$(brew bundle install --file=Brewfile 2>/dev/null | grep -c "^Installing" || true)
    [ "$added" -gt 0 ] && note "env: installed $added new brew packages"
  }
else
  note "⚠️ migration repo not under git yet — run: git init && add a private remote"
fi

# --- 2. code: every repo in ~/Sites ------------------------------------------
pulled=0 dirty=0 snapshotted=0
for dir in "$SITES"/*/; do
  [ -d "$dir/.git" ] || continue
  name=$(basename "$dir")
  git -C "$dir" remote get-url origin >/dev/null 2>&1 || continue
  git -C "$dir" fetch -q --all 2>/dev/null || { note "⚠️ $name: fetch failed"; continue; }
  if [ -z "$(git -C "$dir" status --porcelain)" ]; then
    if ! git -C "$dir" pull -q --ff-only 2>/dev/null; then
      note "⚠️ $name: clean but not fast-forwardable (diverged) — needs a human"
    else pulled=$((pulled+1)); fi
  else
    dirty=$((dirty+1))
    snap=$(git -C "$dir" stash create 2>/dev/null)
    if [ -n "$snap" ] && git -C "$dir" push -q origin "$snap:refs/heads/wip/$HOST" -f 2>/dev/null; then
      snapshotted=$((snapshotted+1))
    fi
    # nudge if dirty > 2 days (oldest modified tracked file as proxy)
    last=$(git -C "$dir" log -1 --format=%ct 2>/dev/null || echo 0)
    age_days=$(( ($(date +%s) - last) / 86400 ))
    [ "$age_days" -ge 2 ] && note "✏️ $name: uncommitted changes, last commit ${age_days}d ago — commit soon?"
  fi
done
note "code: $pulled pulled, $dirty dirty ($snapshotted snapshotted to wip/$HOST)"

# --- 3. report ----------------------------------------------------------------
SUMMARY=$(printf '%s\n' "${REPORT[@]}")
echo "$SUMMARY"
if [ -f sync.config ]; then
  # sync.config: NTFY_URL=https://ntfy.sh/your-secret-topic
  . ./sync.config
  [ -n "${NTFY_URL:-}" ] && curl -s -H "Title: ☀️ $HOST sync" -d "$SUMMARY" "$NTFY_URL" >/dev/null
else
  osascript -e "display notification \"$(echo "$SUMMARY" | head -3 | tr '\n' ' ')\" with title \"☀️ $HOST sync\"" 2>/dev/null
fi
