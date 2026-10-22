#!/bin/bash
# linkblend-supervisor - keeps one net-merge process alive for LinkBlend.
#
# Design: net-merge cannot change its adapter list without closing its tunnel, and
# closing the tunnel briefly breaks every connection. So the process is started once
# with the full candidate list and is left alone:
#   * `-include` acts as a filter, and adapters that are absent at start join when they
#     appear (3 s rescan), so plugging or unplugging a phone never needs a restart.
#   * Linking or unlinking is done by LinkBlend with `networksetup`, which changes the
#     interface addresses only; the tunnel stays up, so the remaining links keep working.
#   * The only restart is an explicit merge/pause switch, and even then the tunnel comes
#     back within a couple of seconds on whichever link works.
#
# Args: <conf dir>
#   candidates.conf  every candidate interface, one per line
#   excluded.conf    interfaces to keep out of the tunnel
#   weights.conf     optional, lines of "en0=2"
#   weightmode       auto | manual
#   ipv6 / mtu / rescan / pprof   engine flags, one value per file

set -u

CONF=${1:?conf dir}
# net-merge is installed twice: the Homebrew copy (used for CLI work) and a
# root copy at /usr/local/bin (what this supervisor runs as root). Prefer the
# root copy, and fall back to Homebrew so a machine that only ran the Homebrew
# install still works.
BIN=/usr/local/bin/net-merge
[ -x "$BIN" ] || BIN=/opt/homebrew/bin/net-merge
LOG=/var/log/linkblend.log
LOCK="$CONF/supervisor.pid"
child=""

if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  echo "$(date '+%F %T') supervisor already running (pid $(cat "$LOCK"))" >>"$LOG"
  exit 0
fi
echo $$ >"$LOCK"

log() { echo "$(date '+%F %T') $*" >>"$LOG"; }

stop_child() {
  [ -z "$child" ] && return
  kill -TERM "$child" 2>/dev/null
  wait "$child" 2>/dev/null
  child=""
  "$BIN" cleanup >>"$LOG" 2>&1
  log "stopped"
}

trap 'stop_child; rm -f "$LOCK"' EXIT
trap 'exit 0' INT TERM

# Clear orphans from an earlier supervisor.
for p in $(pgrep -f "^$BIN run " 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done
sleep 1

conf_weights() { grep -v '^[[:space:]]*$' "$CONF/weights.conf" 2>/dev/null | paste -sd, -; }
conf_candidates() { grep -v '^[[:space:]]*$' "$CONF/candidates.conf" 2>/dev/null | paste -sd, -; }
conf_excluded() { grep -v '^[[:space:]]*$' "$CONF/excluded.conf" 2>/dev/null | paste -sd, -; }

# The include list is a superset: configured candidates plus every adapter
# name a future USB tether can take, minus exclusions. net-merge filters by
# name and probes each adapter for a default route and real internet, so
# names that do not exist yet cost nothing. An adapter plugged in later
# joins the running tunnel on the next rescan; the tunnel is never rebuilt
# just because hardware came or went.
build_include() {
  local excl=" $(conf_excluded | tr ',' ' ') "
  local seen=" " out="" n i oldIFS=$IFS
  IFS=,
  for n in $(conf_candidates); do
    case "$excl" in *" $n "*) continue ;; esac
    case "$seen" in *" $n "*) continue ;; esac
    seen="$seen$n "; out="${out:+$out,}$n"
  done
  IFS=$oldIFS
  for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    n="en$i"
    case "$excl" in *" $n "*) continue ;; esac
    case "$seen" in *" $n "*) continue ;; esac
    seen="$seen$n "; out="${out:+$out,}$n"
  done
  for i in 0 1 2 3 4; do
    n="feth$i"
    case "$excl" in *" $n "*) continue ;; esac
    case "$seen" in *" $n "*) continue ;; esac
    seen="$seen$n "; out="${out:+$out,}$n"
  done
  echo "$out"
}

conf_value() { cat "$CONF/$1" 2>/dev/null || echo "$2"; }

start_child() {
  local include weights args w mode ipv6 mtu rescan
  # Always start with every candidate. Pausing is handled by unlinking services,
  # so the process never needs to restart and the tunnel stays up.
  include=$(build_include)
  weights=$(conf_weights)
  if [ -z "${include:-}" ]; then
    log "no candidates configured; tunnel stays down"
    return 1
  fi

  mode=$(conf_value weightmode auto)
  ipv6=$(conf_value ipv6 auto)
  mtu=$(conf_value mtu 9000)
  rescan=$(conf_value rescan 3)
  pprof=$(conf_value pprof off)

  args=(-include "$include" -stats 0 -log /var/log/linkblend-run.log
        -ipv6 "$ipv6" -mtu "$mtu" -rescan "${rescan}s")
  if [ "$pprof" = "on" ]; then
    args+=(-pprof 127.0.0.1:6060)
  fi
  # Passing any -weight disables net-merge auto-weighting, so fixed weights
  # are only sent in manual mode.
  if [ "$mode" = "manual" ] && [ -n "$weights" ]; then
    local IFS=,
    for w in $weights; do args+=(-weight "$w"); done
    unset IFS
  fi

  "$BIN" run "${args[@]}" >>"$LOG" 2>&1 &
  child=$!
  log "started pid=$child include=$include mode=$mode ipv6=$ipv6 mtu=$mtu rescan=${rescan}s weights=${weights:-auto}"
  return 0
}

log "supervisor up conf=$CONF"
start_child || true

while true; do
  sleep 2

  if [ -z "$child" ] || ! kill -0 "$child" 2>/dev/null; then
    log "net-merge exited; restarting"
    child=""
    start_child || true
  fi
done
