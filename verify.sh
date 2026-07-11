#!/bin/bash
# verify.sh — functional probe suite: asserts the machine BEHAVES correctly, not
# just that files exist. Run on the source Mac to record a green baseline; run on
# the target after bootstrap/wizard; migration is done when the diff is empty.
# Probes derive from manifests AND live scans — stale manifests can't fool it.
# Output: manifest/verify-<hostname>.tsv  (+ a diff vs any other machine's file)
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
OUT="manifest/verify-$HOST.tsv"
SITES="$SITES_DIR"
PASS=0; FAIL=0
: > "$OUT"

probe() { # probe <id> <cmd...>
  local id="$1"; shift
  if eval "$@" >/dev/null 2>&1; then
    printf "%s\tpass\n" "$id" >> "$OUT"; PASS=$((PASS+1)); echo "  ✓ $id"
  else
    printf "%s\tfail\n" "$id" >> "$OUT"; FAIL=$((FAIL+1)); echo "  ✗ $id"
  fi
}

echo "── core commands"
for cmd in git direnv node npm bun supabase gh docker rustup code; do
  probe "cmd:$cmd" "command -v $cmd"
done
probe "auth:gh" "gh auth status"
probe "auth:docker-daemon" "docker info"

echo "── direnv per project (live scan)"
for dir in "$SITES"/*/; do
  [ -f "$dir/.envrc" ] || continue
  name=$(basename "$dir")
  probe "direnv-loads:$name" "direnv exec '$dir' true"
  if grep -q "SUPABASE_ACCESS_TOKEN" "$dir/.envrc"; then
    probe "direnv-token:$name" "direnv exec '$dir' sh -c '[ -n \"\$SUPABASE_ACCESS_TOKEN\" ]'"
  fi
done

echo "── keychain items"
while IFS=$'\t' read -r service account; do
  [ -n "$service" ] && probe "keychain:$service" "security find-generic-password -s '$service' -a '$account'"
done < manifest/keychain-items.tsv

echo "── repo remotes authenticate"
export GIT_SSH_COMMAND="ssh -o ConnectTimeout=6 -o BatchMode=yes"
tail -n +2 manifest/repos.tsv | while IFS=$'\t' read -r name remote branch; do
  [ "$remote" = "NO_REMOTE" ] && continue
  probe "repo-auth:$name" "git ls-remote --exit-code '$remote' HEAD"
done
# subshell above can't update counters; recount from file at the end

echo "── env files present (live scan)"
for f in $(find "$SITES" -maxdepth 3 \( -name ".env" -o -name ".env.local" -o -name ".env.*.local" -o -name ".envrc" \) -not -path "*/node_modules/*" 2>/dev/null); do
  probe "envfile:${f#$SITES/}" "[ -s '$f' ]"
done

echo "── applications present"
tail -n +2 manifest/applications.tsv 2>/dev/null | cut -f1 | while read -r app; do
  probe "app:$app" "[ -d '/Applications/$app.app' ] || [ -d \"\$HOME/Applications/$app.app\" ]"
done

echo "── brew formulae installed"
installed=$(brew list --formula 2>/dev/null)
grep '^brew "' Brewfile | sed 's/brew "\(.*\)".*/\1/' | while read -r f; do
  probe "brew:${f##*/}" "echo '$installed' | grep -qw '${f##*/}'"
done

echo "── docker volumes (local DB data)"
vols=$(docker volume ls --format '{{.Name}}' 2>/dev/null)
grep -o '^supabase_[a-zA-Z0-9_-]*' manifest/databases.txt 2>/dev/null | while read -r v; do
  probe "volume:$v" "echo '$vols' | grep -qx '$v'"
done

echo "── functional: node executes"
probe "func:node-hello" "node -e 'process.exit(0)'"

# recount (probes inside while-subshells didn't hit the parent counters)
PASS=$(grep -c "	pass$" "$OUT"); FAIL=$(grep -c "	fail$" "$OUT")
echo
echo "═══ $HOST: $PASS pass, $FAIL fail → $OUT ═══"

# diff against any other machine's baseline
for other in manifest/verify-*.tsv; do
  [ "$other" = "$OUT" ] && continue
  oh=$(basename "$other" .tsv | sed 's/verify-//')
  echo
  echo "── diff vs $oh (probes green there but not here = your gaps):"
  gaps=0
  while IFS=$'\t' read -r id status; do
    [ "$status" = "pass" ] || continue
    grep -q "^$id	pass$" "$OUT" || { echo "   ✗ $id (passes on $oh)"; gaps=$((gaps+1)); }
  done < "$other"
  [ "$gaps" -eq 0 ] && echo "   ✅ empty diff — this machine behaves like $oh"
done
