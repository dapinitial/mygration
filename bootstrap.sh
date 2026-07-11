#!/bin/bash
# bootstrap.sh — converge a Mac (designed for the Apple Silicon MacBook) to the
# state captured in this repo's manifests. Safe to re-run; it skips what exists.
set -uo pipefail
# load user config (see mygration.conf.example)
MYG_CONF="$(cd "$(dirname "$0")" && pwd)/mygration.conf"
[ -f "$MYG_CONF" ] && . "$MYG_CONF"
MYG_USER="${MYG_USER:-$(whoami)}"
SITES_DIR="${SITES_DIR:-$HOME/Sites}"
SOURCE_HOST="${SOURCE_HOST:-old-mac}"
SOURCE_HOME="${SOURCE_HOME:-/Users/$MYG_USER}"
cd "$(dirname "$0")"

SITES="$SITES_DIR"
mkdir -p "$SITES"

echo "==> Xcode Command Line Tools"
xcode-select -p >/dev/null 2>&1 || { xcode-select --install; echo "Re-run after CLT install finishes."; exit 1; }

echo "==> Homebrew (arm64 at /opt/homebrew)"
if [ ! -x /opt/homebrew/bin/brew ]; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

echo "==> Installing packages from Brewfile"
brew bundle --file=Brewfile

echo "==> Dotfiles (existing files backed up as *.pre-migration)"
while IFS= read -r f; do
  src="dotfiles/${f//\//__}"
  dest="$HOME/$f"
  [ -f "$src" ] || continue
  mkdir -p "$(dirname "$dest")"
  [ -f "$dest" ] && cp "$dest" "$dest.pre-migration"
  cp "$src" "$dest"
  echo "    $f"
done < manifest/dotfiles.txt
if grep -rq "/usr/local" dotfiles/ 2>/dev/null; then
  echo "  ⚠️  Dotfiles reference /usr/local (Intel Homebrew) — update those lines to /opt/homebrew."
fi

echo "==> direnv hook"
grep -q 'direnv hook zsh' "$HOME/.zshrc" 2>/dev/null || echo 'eval "$(direnv hook zsh)"' >> "$HOME/.zshrc"

echo "==> Node via nvm"
if [ ! -d "$HOME/.nvm" ]; then
  brew list nvm >/dev/null 2>&1 || brew install nvm
  mkdir -p "$HOME/.nvm"
fi
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix nvm)/nvm.sh" ] && . "$(brew --prefix nvm)/nvm.sh"
grep '^v' manifest/node.txt | while read -r v; do nvm install "$v"; done
default=$(tail -1 manifest/node.txt)
[ -n "$default" ] && nvm alias default "$default" && nvm use default
[ -s manifest/npm-globals.txt ] && xargs npm install -g < manifest/npm-globals.txt

echo "==> Cloning repos into ~/Sites"
# if this machine's SSH key isn't set up with GitHub yet, clone over HTTPS
# (gh's credential helper covers it); remotes stay as recorded — flip to SSH
# later if you like with: git remote set-url origin <ssh-url>
ssh_ok=false
ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated" && ssh_ok=true
tail -n +2 manifest/repos.tsv | while IFS=$'\t' read -r name remote branch; do
  [ "$remote" = "NO_REMOTE" ] && { echo "    ⚠️  $name has no remote — transfer manually"; continue; }
  url="$remote"
  if [ "$ssh_ok" = false ] && [[ "$url" == git@github.com:* ]]; then
    url="https://github.com/${url#git@github.com:}"
  fi
  if [ -d "$SITES/$name" ]; then echo "    ✓ $name (exists)"; else git clone "$url" "$SITES/$name" || echo "    ⚠️  $name: clone failed"; fi
done

echo "==> VS Code extensions"
if command -v code >/dev/null && [ -f manifest/vscode-extensions.txt ]; then
  xargs -L1 code --install-extension < manifest/vscode-extensions.txt
fi

echo "==> Keychain tokens (paste each when prompted; input is hidden)"
while IFS=$'\t' read -r service account; do
  if security find-generic-password -s "$service" -a "$account" >/dev/null 2>&1; then
    echo "    ✓ $service (already in keychain)"; continue
  fi
  read -r -s -p "    Token for '$service' (enter to skip): " token </dev/tty; echo
  [ -n "$token" ] && security add-generic-password -U -s "$service" -a "$account" -w "$token"
done < manifest/keychain-items.tsv

if [ -f secrets.tar.gz.enc ]; then
  echo "==> Decrypting env files bundle into \$HOME (passphrase prompt)"
  openssl enc -d -aes-256-cbc -pbkdf2 -in secrets.tar.gz.enc | (cd "$HOME" && tar xzf -)
else
  echo "==> No secrets bundle found. Transfer these files manually (AirDrop from the old Mac):"
  sed 's/^/      /' manifest/env-files.txt
fi

echo "==> User launch agents (from launchagents/)"
for plist in launchagents/*.plist; do
  [ -f "$plist" ] || continue
  dest="$HOME/Library/LaunchAgents/$(basename "$plist")"
  cp "$plist" "$dest"
  launchctl unload "$dest" 2>/dev/null; launchctl load "$dest"
  echo "    ✓ $(basename "$plist")"
done

echo "==> Restoring Claude Code agent state (memory, skills, agents)"
AS="agent-state/claude"
if [ -d "$AS" ]; then
  mkdir -p "$HOME/.claude"
  for d in memory skills agents plugins plans; do
    [ -d "$AS/$d" ] && rsync -a "$AS/$d/" "$HOME/.claude/$d/" && echo "    ✓ $d"
  done
  [ -f "$AS/history.jsonl" ] && [ ! -f "$HOME/.claude/history.jsonl" ] && cp "$AS/history.jsonl" "$HOME/.claude/"
  for f in CLAUDE.md settings.json keybindings.json; do
    [ -f "$AS/$f" ] && [ ! -f "$HOME/.claude/$f" ] && cp "$AS/$f" "$HOME/.claude/$f"
  done
  # per-project memory: re-key source-machine home to this home
  OLDKEY=$(echo "$SOURCE_HOME" | tr '/' '-')
  NEWKEY=$(echo "$HOME" | tr '/' '-')
  for src in "$AS/project-memory"/*/; do
    [ -d "$src" ] || continue
    proj=$(basename "$src")
    dest="$HOME/.claude/projects/${proj/#$OLDKEY/$NEWKEY}/memory"
    mkdir -p "$dest" && rsync -a "$src" "$dest/" && echo "    ✓ memory: ${proj/#$OLDKEY/$NEWKEY}"
  done
  echo "    ⓘ ~/.claude.json captured as $AS/dot-claude.json — review MCP entries"
  echo "      and merge by hand (it embeds machine paths; not a drop-in)."
  echo "    ⓘ Sign into Claude Code fresh:  claude  (OAuth lives in Keychain, per-machine)"
fi

echo "==> direnv allow for captured projects"
for dir in "$SITES"/*/; do
  [ -f "$dir/.envrc" ] && direnv allow "$dir" 2>/dev/null && echo "    ✓ $(basename "$dir")"
done

echo
echo "✅ Bootstrap complete. Remaining manual steps:"
echo "   1. New SSH key:  ssh-keygen -t ed25519 -C \"$(whoami)@$(hostname -s)\""
echo "      then add ~/.ssh/id_ed25519.pub to GitHub/servers (don't copy old keys over)."
echo "   2. Run 'npm install' (or equivalent) inside each project as you first open it."
echo "   3. Supabase CLI: tokens above handle auth per-project via direnv."
