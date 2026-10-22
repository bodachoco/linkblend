#!/bin/bash
# install.sh - one-time setup for LinkBlend on a fresh machine.
#
# Creates everything the app expects to already exist:
#   /usr/local/bin/linkblend-supervisor                  root supervisor script
#   /usr/local/var/linkblend/                            config dir it reads
#   /etc/sudoers.d/linkblend                             lets the app start it with no prompt
#   /Applications/LinkBlend.app                          the app itself
#
# It also enables net-merge's own sudoers rule, which needs root. Run this
# once, then use Scripts/update.sh for later versions.
#
# Usage: ./Scripts/install.sh
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
SUPERVISOR_BIN=/usr/local/bin/linkblend-supervisor
CONF=/usr/local/var/linkblend
SUDOERS=/etc/sudoers.d/linkblend
APP=/Applications/LinkBlend.app
USER_NAME=$(whoami)
BREW=$(command -v brew || echo /opt/homebrew/bin/brew)

step() { echo "== $*"; }
fail() { echo "error: $*" >&2; exit 1; }

step "Checking prerequisites"
[ "$(uname -s)" = "Darwin" ] || fail "LinkBlend runs on macOS only."
if [ "$(uname -m)" != "arm64" ]; then
  echo "warning: build.sh targets arm64; adjust -target in build.sh for Intel."
fi

# macOS 26 SDK is required: the UI uses Liquid Glass (glassEffect) and the
# Window scene, both of which need the macOS 26 SDK.
SDK_MAJOR=$(xcrun --show-sdk-version 2>/dev/null | cut -d. -f1 || echo 0)
[ "${SDK_MAJOR:-0}" -ge 26 ] || fail "macOS 26 SDK required (found ${SDK_MAJOR:-none}). Install Xcode 26 or newer."

if ! "$BREW" list net-merge >/dev/null 2>&1; then
  step "Installing net-merge (the bonding engine)"
  "$BREW" install rohit267/tap/net-merge || fail "brew install rohit267/tap/net-merge failed."
fi
NET_MERGE=$("$BREW" --prefix net-merge)/bin/net-merge
[ -x "$NET_MERGE" ] || fail "net-merge binary not found at $NET_MERGE"

if ! "$BREW" list terminal-notifier >/dev/null 2>&1; then
  step "Installing terminal-notifier (optional, for notifications)"
  "$BREW" install terminal-notifier || echo "warning: notifications will be unavailable."
fi

step "Enabling net-merge root helper (asks for your password)"
# Ask for the password once, then keep the sudo timestamp alive for the rest
# of the script so the later steps do not prompt again.
sudo -v || fail "administrator access is required."
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT
# net-merge creates a virtual adapter, which needs root. Its own install
# command writes the sudoers rule that lets the engine start without a prompt.
sudo "$NET_MERGE" install

step "Creating config directory"
sudo mkdir -p "$CONF"
sudo chown "$USER_NAME" "$CONF"
# Logs are written by root-owned processes, so make them group-readable by the user.
sudo touch /var/log/linkblend.log /var/log/linkblend-run.log
sudo chown root:staff /var/log/linkblend.log /var/log/linkblend-run.log 2>/dev/null || true
sudo chmod 664 /var/log/linkblend.log /var/log/linkblend-run.log

step "Installing supervisor"
sudo cp "$SRC/Scripts/supervisor.sh" "$SUPERVISOR_BIN"
sudo chown root:wheel "$SUPERVISOR_BIN"
sudo chmod 755 "$SUPERVISOR_BIN"

step "Writing sudoers rule for $USER_NAME"
# Only this one script is allowed, and only as root. Use a temp file plus
# visudo -c so a syntax error can never lock out sudo.
TMP_SUDOERS=$(mktemp)
cat > "$TMP_SUDOERS" <<EOF
# Written by LinkBlend (install.sh): start the root supervisor without a password prompt.
$USER_NAME ALL=(root) NOPASSWD: $SUPERVISOR_BIN
EOF
chmod 440 "$TMP_SUDOERS"
if sudo visudo -c -f "$TMP_SUDOERS" >/dev/null; then
  sudo chown root:wheel "$TMP_SUDOERS"
  sudo mv "$TMP_SUDOERS" "$SUDOERS"
  echo "installed $SUDOERS"
else
  rm -f "$TMP_SUDOERS"
  fail "generated sudoers file failed validation; nothing was installed."
fi

step "Building the app"
"$SRC/Scripts/build.sh"

step "Registering login item"
# The app manages its own LaunchAgent; nothing to do here beyond making sure
# a stale entry cannot override the freshly copied bundle.
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.linkblend.plist" 2>/dev/null || true

step "Starting LinkBlend"
open "$APP"
sleep 2
if pgrep -f "$APP/Contents/MacOS/LinkBlend" >/dev/null 2>&1; then
  echo "LinkBlend is running."
else
  echo "LinkBlend did not start; open it from /Applications and check Console."
fi

cat <<'EOF'

Done. What happens next:
  1. LinkBlend starts the supervisor, which starts net-merge.
  2. Merging begins with every connection that has an address.

Notes:
  * The engine is the same one you installed with Homebrew; LinkBlend only
    starts and configures it. To use it by hand, run: net-merge status
  * Re-run this script after `brew upgrade net-merge`, since the upgrade
    replaces the binary that the root helper points at.
  * For later LinkBlend versions, run update.sh instead.
EOF
