#!/bin/bash
# install-sync.sh — install the launchd job that runs sync.sh nightly at 3:33am.
# launchd (unlike cron) runs the job after wake if the Mac slept through it.
# Re-run to update. Uninstall: launchctl unload + rm the plist.
set -euo pipefail
# load user config (see mygration.conf.example)
MYG_CONF="$(cd "$(dirname "$0")" && pwd)/mygration.conf"
[ -f "$MYG_CONF" ] && . "$MYG_CONF"
MYG_USER="${MYG_USER:-$(whoami)}"
SITES_DIR="${SITES_DIR:-$HOME/Sites}"
SOURCE_HOST="${SOURCE_HOST:-old-mac}"
SOURCE_HOME="${SOURCE_HOME:-/Users/$MYG_USER}"
REPO="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.mygration.sync.plist"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.mygration.sync</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>$REPO/sync.sh</string>
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>3</integer>
    <key>Minute</key><integer>33</integer>
  </dict>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key><string>$REPO/manifest/sync-$(hostname -s).log</string>
  <key>StandardErrorPath</key><string>$REPO/manifest/sync-$(hostname -s).log</string>
</dict></plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "✅ nightly sync installed (3:33am, logs to manifest/sync-$(hostname -s).log)"
echo "   test now with:  launchctl start com.mygration.sync"
