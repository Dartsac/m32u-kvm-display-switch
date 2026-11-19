#!/bin/bash
# Installs toggle-mirror.sh and the KVM watcher for the current user, and starts the watcher at login.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

BIN_DIR="$HOME/bin"
LABEL="local.m32u-kvm-display-watcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/m32u-kvm-display-watcher.log"

command -v displayplacer >/dev/null || { echo "Missing displayplacer. Run: brew install displayplacer" >&2; exit 1; }
command -v swiftc >/dev/null || { echo "Missing swiftc. Run: xcode-select --install" >&2; exit 1; }

mkdir -p "$BIN_DIR" "$(dirname "$PLIST")" "$(dirname "$LOG")"
install -m 755 toggle-mirror.sh "$BIN_DIR/toggle-mirror.sh"
swiftc -O kvm-display-watcher.swift -o "$BIN_DIR/kvm-display-watcher"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_DIR/kvm-display-watcher</string>
    <string>$BIN_DIR/toggle-mirror.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>$LOG</string>
  <key>StandardErrorPath</key>
  <string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed. Watcher log: $LOG"
