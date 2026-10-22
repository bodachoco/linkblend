#!/bin/bash
# update.sh - clean LinkBlend update.
#
# Order matters:
#   1. Build and stage the new app while everything keeps running.
#   2. Quit the app gracefully.
#   3. Stop the supervisor; its trap stops net-merge and cleans up.
#   4. Swap the app bundle and the supervisor (new inode via mv).
#   5. Relaunch the app; it starts the supervisor, which starts the engine.
#
# This script never touches network services, routes, or DNS. When
# net-merge exits it removes its own overlay routes, and the macOS
# default route carries traffic the whole time.
set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP=/Applications/LinkBlend.app
CONF=/usr/local/var/linkblend
PLIST="$HOME/Library/LaunchAgents/local.linkblend.plist"
USER_ID=$(id -u)

step() { echo "== $*"; }

default_iface() {
  route -n get default 2>/dev/null | awk '/interface:/{print $2}'
}

wait_gone() {
  # $1 = pgrep pattern, $2 = seconds
  local pattern=$1 limit=$2 i=0
  while pgrep -f "$pattern" >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -gt "$limit" ] && return 1
    sleep 1
  done
  return 0
}

ROUTE_BEFORE=$(default_iface)
step "Default route before: ${ROUTE_BEFORE:-unknown}"

# The engine and supervisor are separate root processes. If the supervisor
# script did not change, an app update must not restart them: quitting and
# relaunching the app alone cannot disturb the tunnel.
ENGINE_BEFORE=$(pgrep -f 'net-merge run' | head -n1 || true)
SUP_CHANGED=0
cmp -s "$SRC/Scripts/supervisor.sh" /usr/local/bin/linkblend-supervisor 2>/dev/null || SUP_CHANGED=1
echo "supervisor changed: $SUP_CHANGED (engine pid before: ${ENGINE_BEFORE:-none})"

step "Building (staged)"
STAGE_ONLY=1 "$SRC/Scripts/build.sh" >/dev/null || { echo "build failed"; exit 1; }

step "Quitting LinkBlend"
osascript -e 'tell application "LinkBlend" to quit' >/dev/null 2>&1 || true
if ! wait_gone "$APP/Contents/MacOS/LinkBlend" 5; then
  pkill -f "$APP/Contents/MacOS/LinkBlend" 2>/dev/null || true
  wait_gone "$APP/Contents/MacOS/LinkBlend" 3 || true
fi

if [ "$SUP_CHANGED" = "1" ]; then
step "Stopping supervisor and engine (supervisor changed)"
SUP_PID=$(cat "$CONF/supervisor.pid" 2>/dev/null || true)
if [ -n "${SUP_PID:-}" ]; then
  sudo -n kill "$SUP_PID" 2>/dev/null || true
fi
if ! wait_gone 'linkblend-supervisor' 6; then
  if [ -n "${SUP_PID:-}" ]; then
    sudo -n kill -9 "$SUP_PID" 2>/dev/null || true
  fi
  wait_gone 'linkblend-supervisor' 3 || true
fi
if ! wait_gone 'net-merge run' 5; then
  /opt/homebrew/bin/net-merge off >/dev/null 2>&1 || true
  wait_gone 'net-merge run' 4 || true
fi
if pgrep -f 'linkblend-supervisor|net-merge run' >/dev/null 2>&1; then
  echo "old processes still running; aborting swap"
  pgrep -af 'linkblend-supervisor|net-merge run'
  exit 1
fi

step "Installing supervisor"
if sudo -n cp "$SRC/Scripts/supervisor.sh" /usr/local/bin/linkblend-supervisor.new 2>/dev/null \
  && sudo -n mv /usr/local/bin/linkblend-supervisor.new /usr/local/bin/linkblend-supervisor 2>/dev/null \
  && sudo -n chmod 755 /usr/local/bin/linkblend-supervisor 2>/dev/null; then
  echo "supervisor updated"
else
  echo "supervisor NOT updated (sudo unavailable); new supervisor applies at next start"
fi
else
  step "Supervisor unchanged — engine left running"
fi

step "Installing app"
rm -rf "$APP"
cp -R "$SRC/build/LinkBlend.app" "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

step "Relaunching"
launchctl bootout "gui/$USER_ID" "$PLIST" 2>/dev/null || true
if [ -f "$PLIST" ]; then
  launchctl bootstrap "gui/$USER_ID" "$PLIST" 2>/dev/null || open "$APP"
else
  open "$APP"
fi

step "Verifying"
ok=0
for _ in $(seq 1 30); do
  if pgrep -f "$APP/Contents/MacOS/LinkBlend" >/dev/null 2>&1 \
    && pgrep -f 'linkblend-supervisor' >/dev/null 2>&1 \
    && pgrep -f 'net-merge run' >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 1
done
ROUTE_AFTER=$(default_iface)
echo "app pid:        $(pgrep -f "$APP/Contents/MacOS/LinkBlend" | head -n1)"
echo "supervisor pid: $(pgrep -f 'linkblend-supervisor' | head -n1)"
echo "engine pid:     before=${ENGINE_BEFORE:-?} after=$(pgrep -f 'net-merge run' | head -n1)"
echo "default route:  before=${ROUTE_BEFORE:-?} after=${ROUTE_AFTER:-?}"
python3 - << 'PY' 2>/dev/null || true
import json
try:
    d = json.load(open("/var/run/net-merge/status.json"))
    print("tunnel NICs:   ", [n["Name"] for n in d["NICs"]], "engine pid", d["PID"])
except Exception as e:
    print("tunnel NICs:    status not readable yet", e)
PY
[ "$ok" = "1" ] && echo "UPDATE OK" || { echo "UPDATE INCOMPLETE"; exit 1; }
