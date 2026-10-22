#!/bin/bash
# uninstall.sh - remove LinkBlend and everything install.sh created.
#
# The app, its login item, and the user-level data go without sudo. The two
# root-owned pieces (the supervisor binary and the sudoers rule) are listed
# for you to remove, because deleting a sudoers rule as the user whose rule
# it is needs root.
set -u

APP=/Applications/LinkBlend.app
SUPERVISOR=/usr/local/bin/linkblend-supervisor
SUDOERS=/etc/sudoers.d/linkblend
CONF=/usr/local/var/linkblend
PLIST="$HOME/Library/LaunchAgents/local.linkblend.plist"
SUPPORT="$HOME/Library/Application Support/LinkBlend"
USER_ID=$(id -u)

step() { echo "== $*"; }

step "Stopping the supervisor and engine"
# The supervisor watches this file, and its exit trap stops net-merge.
touch "$CONF/stop" 2>/dev/null || true
for _ in $(seq 1 8); do
  pgrep -f 'linkblend-supervisor' >/dev/null 2>&1 || break
  sleep 1
done
if pgrep -f 'linkblend-supervisor|net-merge run' >/dev/null 2>&1; then
  echo "Processes still running; stop them with:"
  echo "  sudo pkill -f linkblend-supervisor"
  echo "  /opt/homebrew/bin/net-merge off"
fi

step "Removing the app"
launchctl bootout "gui/$USER_ID" "$PLIST" 2>/dev/null || true
pkill -f "$APP/Contents/MacOS/LinkBlend" 2>/dev/null || true
sleep 1
rm -rf "$APP"
rm -f "$PLIST"

step "Removing user data"
rm -rf "$SUPPORT"

step "Left in place (remove with sudo)"
echo "  sudo rm -f $SUPERVISOR"
echo "  sudo rm -f $SUDOERS"
echo "  sudo rm -rf $CONF /var/log/linkblend.log /var/log/linkblend-run.log"
echo
echo "The net-merge formula itself is a Homebrew package; remove it with:"
echo "  brew uninstall net-merge"
