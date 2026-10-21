#!/bin/bash
# Builds ThumbMap, installs it to ~/Applications, and starts it at login via launchd.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.local.thumbmap"
APP="$HOME/Applications/ThumbMap.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONF_DIR="$HOME/.config/thumbmap"
LOG="$HOME/Library/Logs/ThumbMap.log"
DOMAIN="gui/$(id -u)"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "The Swift compiler is missing. Run:  xcode-select --install   then re-run this script."
  exit 1
fi

UPGRADE=0
[ -d "$APP" ] && UPGRADE=1

echo "→ Stopping any running copy…"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

echo "→ Building…"
mkdir -p "$APP/Contents/MacOS" "$CONF_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
swiftc -O -swift-version 5 \
  -framework Cocoa -framework ApplicationServices \
  -o "$APP/Contents/MacOS/ThumbMap" "$HERE/ThumbMap.swift"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - --identifier "$LABEL" "$APP"

if [ ! -f "$CONF_DIR/config.json" ]; then
  cp "$HERE/config.json" "$CONF_DIR/config.json"
  echo "→ Wrote default config to $CONF_DIR/config.json"
else
  echo "→ Kept your existing config at $CONF_DIR/config.json"
fi

if [ "$UPGRADE" = "1" ]; then
  # A rebuilt binary has a new signature, so the old Accessibility grant no longer applies.
  echo "→ Resetting the stale Accessibility grant (you will be asked to approve again)…"
  tccutil reset Accessibility "$LABEL" >/dev/null 2>&1 || true
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APP/Contents/MacOS/ThumbMap</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

echo "→ Starting ThumbMap…"
launchctl bootstrap "$DOMAIN" "$PLIST"

cat <<MSG

ThumbMap is installed and running.

NEXT: approve it in System Settings → Privacy & Security → Accessibility
      (a prompt should appear; if not, add ~/Applications/ThumbMap.app with the + button).

Useful commands:
  Watch button presses / errors:  tail -f "$LOG"
  Reload config after editing:     pkill -HUP -x ThumbMap
  Record helper for Wispr Flow:    pkill -USR1 -x ThumbMap
  Restart:                         launchctl kickstart -k $DOMAIN/$LABEL
  Uninstall:                       "$HERE/uninstall.sh"
MSG
