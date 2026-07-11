#!/bin/bash
# audit.sh — discover everything OUTSIDE the dev-environment manifests that a new
# Mac would need: manual apps, launch agents, docker/db data, hidden configs,
# secret-bearing files, loose files. Writes decision lists to manifest/ for the
# human to review — it never moves or changes anything.
set -uo pipefail
# load user config (see mygration.conf.example)
MYG_CONF="$(cd "$(dirname "$0")" && pwd)/mygration.conf"
[ -f "$MYG_CONF" ] && . "$MYG_CONF"
MYG_USER="${MYG_USER:-$(whoami)}"
SITES_DIR="${SITES_DIR:-$HOME/Sites}"
SOURCE_HOST="${SOURCE_HOST:-old-mac}"
SOURCE_HOME="${SOURCE_HOME:-/Users/$MYG_USER}"
cd "$(dirname "$0")"
mkdir -p manifest

echo "==> Applications (vs Homebrew casks)"
{
  echo -e "# app\tsource_guess"
  casks=$(brew list --cask 2>/dev/null)
  for app in /Applications/*.app ~/Applications/*.app; do
    [ -e "$app" ] || continue
    name=$(basename "$app" .app)
    guess=$(echo "$name" | tr '[:upper:] ' '[:lower:]-' | sed 's/\.//g')
    if echo "$casks" | grep -qix "$guess"; then
      echo -e "$name\tinstalled-via-cask"
    elif brew info --cask "$guess" >/dev/null 2>&1; then
      echo -e "$name\tcask-available:$guess"
    else
      echo -e "$name\tmanual-or-appstore"
    fi
  done
} > manifest/applications.tsv

echo "==> Launch agents & daemons (non-Apple)"
{
  for d in ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons; do
    ls "$d" 2>/dev/null | sed "s|^|$d/|"
  done
} > manifest/launchagents.txt
# Copy user-authored agents (heuristic: not from a known vendor) for restore
mkdir -p launchagents
grep -vE "com\.(google|apple|docker)|us\.zoom" manifest/launchagents.txt \
  | grep "^$HOME" | while read -r plist; do cp "$plist" launchagents/ 2>/dev/null; done

echo "==> Docker volumes & local databases"
{
  echo "# docker volumes (data that does NOT travel via git):"
  docker volume ls --format '{{.Name}}' 2>/dev/null || echo "(docker not running — re-run audit with Docker up)"
  echo "# brew database services:"
  brew services list 2>/dev/null | tail -n +2
} > manifest/databases.txt

echo "==> Hidden configs & secret-bearing files"
{
  echo -e "# path\tclassification"
  # secrets: never plain git — keychain or encrypted bundle
  for p in .npmrc .netrc .git-credentials .secrets .supabase/access-token \
           .config/gh/hosts.yml .aws/credentials .docker/config.json .kube/config \
           .config/gcloud .gnupg; do
    [ -e "$HOME/$p" ] && echo -e "~/$p\tSECRET->encrypted-bundle"
  done
  # plain config: candidates for dotfiles/ capture
  for p in .zshenv .zprofile .zlogin .p10k.zsh .gitignore_global .claude .claude.json \
           .config/git .config/gh/config.yml .cargo/config.toml \
           "Library/Application Support/Code/User/settings.json" \
           "Library/Application Support/Code/User/keybindings.json"; do
    [ -e "$HOME/$p" ] && echo -e "~/$p\tconfig->dotfiles"
  done
} > manifest/hidden-configs.tsv

echo "==> Loose files (user decides: AirDrop / Syncthing / skip)"
{
  echo "# ~/Desktop: $(ls ~/Desktop 2>/dev/null | wc -l | tr -d ' ') items, $(du -sh ~/Desktop 2>/dev/null | cut -f1)"
  echo "# ~/Downloads: $(ls ~/Downloads 2>/dev/null | wc -l | tr -d ' ') items, $(du -sh ~/Downloads 2>/dev/null | cut -f1)"
  echo "# ~/Documents: $(du -sh ~/Documents 2>/dev/null | cut -f1)"
  echo "# non-git items in ~/Sites:"
  for f in ~/Sites/*; do
    [ -d "$f/.git" ] || echo "  $(basename "$f") ($(du -sh "$f" 2>/dev/null | cut -f1))"
  done
} > manifest/loose-files.txt

echo
echo "✅ Audit written to manifest/{applications.tsv,launchagents.txt,databases.txt,hidden-configs.tsv,loose-files.txt}"
echo "   Review manifest/DECISIONS.md and mark your choices."
