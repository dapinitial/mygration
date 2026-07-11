#!/bin/bash
# wizard.sh — guided, resumable setup walkthrough for a new (or existing) Mac.
# Each step shows instructions, then VERIFIES completion itself (no honor system).
# Progress is saved to manifest/setup-state-<hostname>.tsv — commit it and the
# checklist stays in tandem across machines. Re-run anytime; done steps skip.
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
STATE="manifest/setup-state-$HOST.tsv"
mkdir -p manifest; touch "$STATE"

is_done()   { grep -q "^$1	done" "$STATE"; }
mark_done() { grep -v "^$1	" "$STATE" > "$STATE.tmp" || true; mv "$STATE.tmp" "$STATE"; printf "%s\tdone\t%s\n" "$1" "$(date +%Y-%m-%dT%H:%M)" >> "$STATE"; }
mark_skip() { grep -v "^$1	" "$STATE" > "$STATE.tmp" || true; mv "$STATE.tmp" "$STATE"; printf "%s\tskipped\t%s\n" "$1" "$(date +%Y-%m-%dT%H:%M)" >> "$STATE"; }

# run_step <id> — the wizard executes the step itself ([r] option). Interactive
# commands get the terminal. Returns 1 if the step has nothing runnable.
run_step() {
  case "$1" in
    bootstrap) ./bootstrap.sh ;;
    gh)        gh auth login ;;
    sshkey)    ssh-keygen -t ed25519 -C "$(whoami)@$(hostname -s)" \
                 && gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$(hostname -s)" ;;
    supabase)  supabase login ;;
    gcloud)    gcloud auth login ;;
    secrets)   openssl enc -d -aes-256-cbc -pbkdf2 -in secrets.tar.gz.enc | (cd "$HOME" && tar xzf -) ;;
    syncthing) brew install syncthing && brew services start syncthing && open http://127.0.0.1:8384 ;;
    nightly)   ./install-sync.sh ;;
    icloud)    open "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane" ;;
    tailscale) open -a Tailscale ;;
    docker)    open -a Docker ;;
    chrome)    open -a "Google Chrome" ;;
    appstore)  open "macappstore://apps.apple.com/app/xcode/id497799835" ;;
    *) return 1 ;;
  esac
}

# step <id> <title> <verify-cmd> <<'EOF' ...instructions... EOF
step() {
  local id="$1" title="$2" verify="$3" instructions; instructions=$(cat)
  TOTAL=$((TOTAL+1))
  if is_done "$id"; then echo "  ✓ $title"; DONE=$((DONE+1)); return; fi
  if [ -n "$verify" ] && eval "$verify" >/dev/null 2>&1; then
    mark_done "$id"; echo "  ✓ $title (auto-verified)"; DONE=$((DONE+1)); return
  fi
  echo; echo "── ○ $title ──────────────────────────────"
  echo "$instructions" | sed 's/^/   /'
  while true; do
    printf "   [r]=run it for me   [enter]=I did it myself, verify   [s]kip   [q]uit → "
    read -r ans </dev/tty
    case "$ans" in
      r) echo "   ▶ running..."; run_step "$id" </dev/tty || echo "   (no auto-run for this step — follow the instructions above)"
         if [ -n "$verify" ] && eval "$verify" >/dev/null 2>&1; then
           mark_done "$id"; DONE=$((DONE+1)); echo "   ✓ verified!"; return
         else echo "   ran — but not verified yet (may need a manual part above)"; fi ;;
      s) mark_skip "$id"; echo "   ⏭  skipped"; return ;;
      q) summary; exit 0 ;;
      *) if [ -z "$verify" ]; then mark_done "$id"; DONE=$((DONE+1)); echo "   ✓ marked done (no auto-check for this step)"; return
         elif eval "$verify" >/dev/null 2>&1; then mark_done "$id"; DONE=$((DONE+1)); echo "   ✓ verified!"; return
         else
           echo "   ✗ not detected yet. The check I run is:"
           echo "       $verify"
           echo "     Run it yourself to see the error, finish the step, or [s]kip."
         fi ;;
    esac
  done
}

summary() {
  echo; echo "═══ $DONE/$TOTAL done on $HOST ═══"
  echo "Commit the state so the other Mac sees it:"
  echo "  git add '$STATE' && git commit -m 'wizard progress ($HOST)' && git push"
}

TOTAL=0; DONE=0
echo "🧙 Migration wizard — $HOST — progress in $STATE"
echo

step icloud "Sign into iCloud (Apple ID)" \
  "defaults read MobileMeAccounts Accounts 2>/dev/null | grep -q AccountID || [ -d \"\$HOME/Library/Mobile Documents/com~apple~CloudDocs\" ]" <<'EOF'
System Settings → sign in with your Apple ID.
Enable: iCloud Drive (Documents), Safari, Keychain (brings passwords + passkeys).
EOF

step bootstrap "Run bootstrap.sh (brew, apps, dotfiles, repos, node)" \
  "PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH brew bundle check --file=Brewfile" <<'EOF'
In this directory:  ./bootstrap.sh
Installs Homebrew + all packages/casks, dotfiles, clones repos, node versions.
EOF

step tailscale "Sign into Tailscale (joins your tailnet)" \
  "/Applications/Tailscale.app/Contents/MacOS/Tailscale status" <<'EOF'
Open Tailscale.app (installed by bootstrap) → Log in → approve this device.
EOF

step gh "GitHub CLI auth" "gh auth status" <<'EOF'
Run:  gh auth login    (choose GitHub.com, HTTPS or SSH, browser login)
EOF

step sshkey "New SSH key for this machine, added to GitHub" \
  "ls \$HOME/.ssh/id_ed25519.pub && ssh -o BatchMode=yes -T git@github.com 2>&1 | grep -q 'successfully authenticated'" <<'EOF'
Run:  ssh-keygen -t ed25519 -C "$(whoami)@$(hostname -s)"
Then: gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname -s)"
(Per-machine keys — never copy the old Mac's private key.)
EOF

step docker "Docker Desktop running + signed in" "docker info" <<'EOF'
Open Docker.app once (installed by bootstrap), accept the setup, sign in if you
use Docker Hub. Wait for the whale to settle.
EOF

step supabase "Supabase CLI global login" "supabase projects list" <<'EOF'
Run:  supabase login    (opens browser; this is the GLOBAL login — per-project
tokens come next via the keychain step)
EOF

step keychain "Per-project tokens in macOS Keychain" \
  "[ ! -s manifest/keychain-items.tsv ] || ! { while IFS=\$'\t' read -r svc acct; do security find-generic-password -s \"\$svc\" -a \"\$acct\" >/dev/null 2>&1 || echo missing; done < manifest/keychain-items.tsv; } | grep -q missing" <<'EOF'
bootstrap.sh prompts for every token listed in manifest/keychain-items.tsv.
Add one manually:  security add-generic-password -U -s <service> -a "$USER" -w '<token>'
EOF

step gcloud "Google Cloud auth" \
  "gcloud auth list --format='value(account)' 2>/dev/null | grep -q ." <<'EOF'
Run:  gcloud auth login
EOF

step chrome "Chrome profile sync" "" <<'EOF'
Open Chrome → sign into your Google profile → bookmarks/extensions/passwords sync.
(No reliable auto-check; confirm manually.)
EOF

step appstore "App Store installs: Xcode, TestFlight, Developer" \
  "[ -d /Applications/Xcode.app ]" <<'EOF'
App Store → sign in → install Xcode (big download), TestFlight, Developer.
Then run once:  sudo xcodebuild -license accept
EOF

step dbrestore "Restore local database dumps (data-dumps/)" "" <<'EOF'
Dumps are ALREADY in data-dumps/ (they arrive via the encrypted bundle).
Restore is only needed when you first work on one of these projects — safe to
skip now. Per project (Docker Desktop must be running):
  cd ~/Sites/<project> && supabase start
  psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
    -f data-dumps/<project>-schema.sql -f data-dumps/<project>-data.sql
EOF

step secrets "Decrypt env-file bundle (if not done by bootstrap)" \
  "[ ! -s manifest/env-files.txt ] || [ -f \"\$HOME/\$(head -1 manifest/env-files.txt)\" ]" <<'EOF'
bootstrap.sh decrypts secrets.tar.gz.enc automatically if present.
Manual:  openssl enc -d -aes-256-cbc -pbkdf2 -in secrets.tar.gz.enc | (cd ~ && tar xzf -)
EOF

step syncthing "Syncthing paired for non-git folders" \
  "curl -s http://127.0.0.1:8384 -o /dev/null" <<'EOF'
brew install syncthing && brew services start syncthing
Open http://127.0.0.1:8384 → add the other Mac (it appears via Tailscale) →
share the non-git folders you chose in manifest/DECISIONS.
EOF

step nightly "Nightly sync installed (launchd)" \
  "launchctl list | grep -q com.mygration.sync" <<'EOF'
Run:  ./install-sync.sh   (installs the launchd job that runs sync.sh nightly)
EOF

summary
