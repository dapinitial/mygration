# cswap — Claude Code profile hot-swap (spec: specs/claude-profiles.md)
# Install: echo 'source ~/Sites/migration/profiles/cswap.sh' >> ~/.zshrc
cswap() {
  local root="$HOME/.claude-profiles"
  case "${1:-}" in
    ls)
      ls -1 "$root" 2>/dev/null || echo "no profiles yet — cswap init <name>" ;;
    which)
      echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude (default)}" ;;
    off)
      unset CLAUDE_CONFIG_DIR
      echo "→ default profile (~/.claude)" ;;
    init)
      [ -z "${2:-}" ] && { echo "usage: cswap init <name> [--from-default]"; return 1; }
      mkdir -p "$root/$2/config"
      [ -f "$root/$2/env" ] || printf '# sourced on activation, e.g.:\n# export ANTHROPIC_BASE_URL=https://gateway.example.com\n# export ANTHROPIC_API_KEY="$(security find-generic-password -s %s-claude -a $USER -w)"\n' "$2" > "$root/$2/env"
      [ -f "$root/$2/policy.json" ] || printf '{ "sync": true }\n' > "$root/$2/policy.json"
      if [ "${3:-}" = "--from-default" ] && [ -d "$HOME/.claude" ]; then
        rsync -a "$HOME/.claude/" "$root/$2/config/"
        echo "seeded '$2' from ~/.claude"
      fi
      echo "profile '$2' created — activate: cswap $2" ;;
    "")
      echo "usage: cswap <profile>|ls|which|off|init <name> [--from-default]" ;;
    *)
      [ -d "$root/$1/config" ] || { echo "no profile '$1' — cswap init $1"; return 1; }
      export CLAUDE_CONFIG_DIR="$root/$1/config"
      # shellcheck disable=SC1090
      [ -f "$root/$1/env" ] && source "$root/$1/env"
      echo "→ profile '$1' ($CLAUDE_CONFIG_DIR)" ;;
  esac
}
