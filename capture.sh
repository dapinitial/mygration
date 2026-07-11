#!/bin/bash
# capture.sh — snapshot this Mac's dev environment into declarative manifests.
# Run anytime; output is committed to this repo so any machine can converge to it.
#
#   ./capture.sh            capture everything (no secrets ever written)
#   ./capture.sh secrets    additionally bundle gitignored .env files into an
#                           encrypted tarball (secrets.tar.gz.enc) safe to commit
set -euo pipefail
# load user config (see mygration.conf.example)
MYG_CONF="$(cd "$(dirname "$0")" && pwd)/mygration.conf"
[ -f "$MYG_CONF" ] && . "$MYG_CONF"
MYG_USER="${MYG_USER:-$(whoami)}"
SITES_DIR="${SITES_DIR:-$HOME/Sites}"
SOURCE_HOST="${SOURCE_HOST:-old-mac}"
SOURCE_HOME="${SOURCE_HOME:-/Users/$MYG_USER}"
cd "$(dirname "$0")"

SITES="$SITES_DIR"
mkdir -p manifest dotfiles

echo "==> Homebrew packages"
brew bundle dump --file=Brewfile --force
# re-append manual additions the dump can't know about (survives regeneration)
[ -f Brewfile.extras ] && grep -vxF -f Brewfile Brewfile.extras >> Brewfile
# drop entries that are known-broken to auto-install (see Brewfile.exclude)
[ -f Brewfile.exclude ] && { grep -vF -f Brewfile.exclude Brewfile > Brewfile.tmp && mv Brewfile.tmp Brewfile; }
# adopt pre-existing apps instead of reinstalling over them
grep -q "^cask_args adopt" Brewfile || { printf 'cask_args adopt: true\n' | cat - Brewfile > Brewfile.tmp && mv Brewfile.tmp Brewfile; }

echo "==> Git repos in ~/Sites"
{
  echo -e "# name\tremote\tbranch"
  for dir in "$SITES"/*/; do
    name=$(basename "$dir")
    [ -d "$dir/.git" ] || continue
    remote=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "NO_REMOTE")
    branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "?")
    echo -e "$name\t$remote\t$branch"
  done
} > manifest/repos.tsv

# Warn (stdout only) about repos that bootstrap can't restore
for dir in "$SITES"/*/; do
  name=$(basename "$dir")
  if [ ! -d "$dir/.git" ]; then
    [ -d "$dir" ] && echo "  ⚠️  $name: not a git repo — won't be restored by bootstrap"
    continue
  fi
  if ! git -C "$dir" remote get-url origin >/dev/null 2>&1; then
    echo "  ⚠️  $name: no remote — push it somewhere or it won't be restored"
  elif [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    echo "  ⚠️  $name: uncommitted changes"
  elif [ -n "$(git -C "$dir" log --branches --not --remotes --oneline 2>/dev/null)" ]; then
    echo "  ⚠️  $name: unpushed commits"
  fi
done

echo "==> Keychain items referenced by .envrc files (names only, never values)"
grep -h "security find-generic-password" "$SITES"/*/.envrc 2>/dev/null \
  | sed -E 's/.*-s ([^ ]+) -a ([^ ]+).*/\1\t\2/' | sort -u > manifest/keychain-items.tsv

echo "==> Gitignored env files that need manual/encrypted transfer"
find "$SITES" -maxdepth 3 \( -name ".env" -o -name ".env.local" -o -name ".env.*.local" -o -name ".envrc" \) \
  -not -path "*/node_modules/*" 2>/dev/null | sed "s|$HOME/||" | sort > manifest/env-files.txt

echo "==> Node environment"
{
  echo "# installed node versions"
  ls "$HOME/.nvm/versions/node" 2>/dev/null || true
  echo "# default alias"
  cat "$HOME/.nvm/alias/default" 2>/dev/null || true
} > manifest/node.txt
npm ls -g --depth=0 --parseable 2>/dev/null | tail -n +2 | awk -F/ '{print $NF}' \
  | sort > manifest/npm-globals.txt || true

echo "==> VS Code extensions"
command -v code >/dev/null && code --list-extensions > manifest/vscode-extensions.txt || true

echo "==> Dotfiles (scanned for secret-looking strings before copy)"
# NOTE: ~/.claude.json is NEVER captured here — MCP configs embed credentials.
# It travels ONLY inside the encrypted bundle (agent-state/claude/dot-claude.json).
DOTFILES=(.zshrc .zprofile .gitconfig .ssh/config .claude/settings.json
  "Library/Application Support/Code/User/settings.json"
  "Library/Application Support/Code/User/keybindings.json"
  "Library/Application Support/Code/User/chatLanguageModels.json")
: > manifest/dotfiles.txt
for f in "${DOTFILES[@]}"; do
  src="$HOME/$f"
  [ -f "$src" ] || continue
  if grep -qiE "(sbp_|gh[pousr]_|sk-|AKIA|-----BEGIN|dop_v1_|doo_v1_|dor_v1_|glpat-|xox[bpars]-|AIza|npm_[A-Za-z0-9]|_authToken|api[_-]?key.{0,4}[:=])" "$src"; then
    echo "  ⚠️  $f looks like it contains a secret — NOT copied. Clean it up and re-run."
    continue
  fi
  dest="dotfiles/${f//\//__}"   # .ssh/config -> .ssh__config
  cp "$src" "$dest"
  echo "$f" >> manifest/dotfiles.txt
done

echo "==> Agent state (Claude Code memory/skills/agents — the AI's context)"
mkdir -p agent-state/claude
for d in memory skills agents plugins plans; do
  [ -d "$HOME/.claude/$d" ] && rsync -a --delete "$HOME/.claude/$d/" "agent-state/claude/$d/" 2>/dev/null
done
[ -f "$HOME/.claude/history.jsonl" ] && cp "$HOME/.claude/history.jsonl" "agent-state/claude/"
# per-project MEMORY (curated context) — but never session transcripts (huge, may
# contain pasted secrets); project dirs are path-keyed and re-keyed at bootstrap
find "$HOME/.claude/projects" -maxdepth 2 -type d -name memory 2>/dev/null | while read -r m; do
  proj=$(basename "$(dirname "$m")")
  rsync -a --delete "$m/" "agent-state/claude/project-memory/$proj/" 2>/dev/null
done
for f in CLAUDE.md settings.json keybindings.json; do
  [ -f "$HOME/.claude/$f" ] && cp "$HOME/.claude/$f" "agent-state/claude/"
done
# ~/.claude.json holds MCP config but also machine-keyed paths — copy for reference;
# bootstrap treats it as a template, not a drop-in (paths need re-keying on target)
[ -f "$HOME/.claude.json" ] && cp "$HOME/.claude.json" "agent-state/claude/dot-claude.json"

if [ "${1:-}" = "secrets" ]; then
  echo "==> Encrypting env files into secrets.tar.gz.enc (you'll be prompted for a passphrase)"
  # env files + extra secret paths approved in manifest/DECISIONS.md
  bundle_list=$(mktemp)
  cat manifest/env-files.txt > "$bundle_list"
  for extra in .secrets Sites/migration/data-dumps Sites/migration/agent-state; do
    [ -e "$HOME/$extra" ] && echo "$extra" >> "$bundle_list"
  done
  if (cd "$HOME" && tar czf - -T "$bundle_list") \
    | openssl enc -aes-256-cbc -pbkdf2 -salt -out secrets.tar.gz.enc \
    && [ -s secrets.tar.gz.enc ]; then
    echo "    ✓ bundle written ($(du -h secrets.tar.gz.enc | cut -f1))"
  else
    rm -f secrets.tar.gz.enc
    echo "    ✗ encryption failed (passphrase mismatch?) — no bundle written; re-run: ./capture.sh secrets"
  fi
  rm -f "$bundle_list"
  echo "    committed-safe: it's encrypted; decrypt on the new Mac via bootstrap.sh"
fi

echo
echo "✅ Capture complete — review, then: git add -A && git commit -m 'snapshot $(date +%Y-%m-%d)'"
