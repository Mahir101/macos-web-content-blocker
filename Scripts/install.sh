#!/bin/bash
# install.sh — build the blocker, install both LaunchAgents/Daemons,
# and start the service.
#
#   ./Scripts/install.sh
#
# Requires sudo for the root hosts-sync daemon (you'll be prompted).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPPORT_DIR="$HOME/Library/Application Support/PornBlocker"
LOG_DIR="$SUPPORT_DIR/logs"
USER_AGENTS="$HOME/Library/LaunchAgents"
SYSTEM_DAEMONS="/Library/LaunchDaemons"
EXPORT_PATH="$SUPPORT_DIR/blocked-domains.txt"

BLOCKERD_LABEL="com.selfcontrol.pornblocker.blockerd"
HOSTSSYNC_LABEL="com.selfcontrol.pornblocker.hostssync"

echo "==> Building release binaries…"
cd "$REPO_DIR"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BLOCKERD_BIN="$BIN_DIR/blockerd"
APP_BIN="$BIN_DIR/BlockerApp"

mkdir -p "$SUPPORT_DIR" "$LOG_DIR" "$USER_AGENTS"
# Seed an empty export so the hosts daemon has something to watch.
[[ -f "$EXPORT_PATH" ]] || : > "$EXPORT_PATH"

echo "==> Installing blockerd LaunchAgent…"
BLOCKERD_PLIST="$USER_AGENTS/$BLOCKERD_LABEL.plist"
sed -e "s|__EXEC_PATH__|$BLOCKERD_BIN|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    "$REPO_DIR/LaunchAgents/$BLOCKERD_LABEL.plist" > "$BLOCKERD_PLIST"

launchctl bootout "gui/$(id -u)/$BLOCKERD_LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$BLOCKERD_PLIST"
launchctl enable "gui/$(id -u)/$BLOCKERD_LABEL" 2>/dev/null || true

echo "==> Installing root hosts-sync LaunchDaemon (needs sudo)…"
HOSTSSYNC_PLIST_SRC="$REPO_DIR/LaunchAgents/$HOSTSSYNC_LABEL.plist"
HOSTSSYNC_SCRIPT="$REPO_DIR/Scripts/hosts-sync.sh"
chmod +x "$HOSTSSYNC_SCRIPT"

TMP_PLIST="$(mktemp)"
sed -e "s|__SCRIPT_PATH__|$HOSTSSYNC_SCRIPT|g" \
    -e "s|__EXPORT_PATH__|$EXPORT_PATH|g" \
    "$HOSTSSYNC_PLIST_SRC" > "$TMP_PLIST"

sudo cp "$TMP_PLIST" "$SYSTEM_DAEMONS/$HOSTSSYNC_LABEL.plist"
sudo chown root:wheel "$SYSTEM_DAEMONS/$HOSTSSYNC_LABEL.plist"
sudo chmod 644 "$SYSTEM_DAEMONS/$HOSTSSYNC_LABEL.plist"
rm -f "$TMP_PLIST"

sudo launchctl bootout "system/$HOSTSSYNC_LABEL" 2>/dev/null || true
sudo launchctl bootstrap system "$SYSTEM_DAEMONS/$HOSTSSYNC_LABEL.plist"

cat <<EOF

==> Installed.

  Daemon binary : $BLOCKERD_BIN
  Dashboard app : $APP_BIN
  Support dir   : $SUPPORT_DIR

NEXT STEP — grant Accessibility permission:
  System Settings ▸ Privacy & Security ▸ Accessibility
  Enable the entry for: blockerd

The daemon is already running and will begin monitoring the moment the
permission is granted. Launch the dashboard with:

  "$APP_BIN"

EOF
