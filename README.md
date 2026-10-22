# LinkBlend

Combine your Mac's Wi-Fi, Ethernet, and phone tethering into one faster, more resilient connection.

LinkBlend is a native macOS app that wraps the [net-merge](https://github.com/rohit267/net-merge) bonding engine in a windowed interface. It starts the engine, keeps it running, shows live throughput per link, and lets you control every adapter without touching a terminal.

## What it does

- **Merges connections.** Traffic is balanced per flow across every enabled adapter, so a download can use Wi-Fi and a phone tether at the same time.
- **Survives dropouts.** When a link drops, the flows on it move to the remaining links. The tunnel stays up, so open transfers and calls continue.
- **Keeps links ready.** The engine starts with a candidate list that covers every adapter name macOS might assign, so plugging in a phone joins the running tunnel without a restart.
- **Controls each link.** Turn a connection on or off, set its role, cap its daily data, or test its speed individually.
- **Shows what is happening.** Live throughput, per-link rates, 30-day usage history, and session counters.

## Requirements

| Item | Version |
| --- | --- |
| Mac | Apple Silicon |
| macOS | 26 or later |
| Xcode | 26 or later (for the macOS 26 SDK) |
| Homebrew | any recent version |

The macOS 26 SDK is required. The interface uses Liquid Glass (`glassEffect`) and the `Window` scene, neither of which exists in earlier SDKs.

## Install

```bash
git clone https://github.com/bodachoco/linkblend.git
cd linkblend
./Scripts/install.sh        # one-time setup
./Scripts/build.sh          # or just build and install the app
./Scripts/update.sh         # later: safe in-place update
```

`Scripts/install.sh` does the one-time setup and asks for your password as it runs:

1. Installs `net-merge` and `terminal-notifier` through Homebrew.
2. Runs `sudo net-merge install`, which enables net-merge's root helper so the engine can create its virtual adapter without a password prompt.
3. Creates `/usr/local/var/linkblend/` for the engine's configuration.
4. Installs `supervisor.sh` as `/usr/local/bin/linkblend-supervisor`.
5. Writes an `/etc/sudoers.d/linkblend` rule so the app can start that one script as root without a prompt.
6. Builds and installs `/Applications/LinkBlend.app`, then launches it.

Re-run `Scripts/install.sh` after `brew upgrade net-merge`, because the upgrade replaces the binary that the root helper points to.

## Update

```bash
./Scripts/update.sh
```

`Scripts/update.sh` stages the new build first, then swaps it in. It compares `Scripts/supervisor.sh` against the installed copy:

- **Supervisor unchanged:** the app is quit and relaunched. The engine and supervisor keep running, so the tunnel is never interrupted.
- **Supervisor changed:** the supervisor and engine are stopped, the new supervisor is installed, and the app restarts them.

The script never touches network services, routes, or DNS.

## Use

Open LinkBlend from **Applications** or the menu bar. The window has four tabs: **Overview**, **Activity**, **Settings**, and a **Developer** tab that appears when you turn on developer mode.

### Overview

The status line reports **Merged**, **Not merged**, or **Merging off**. Below it is a live chart, then total download and upload rates, then the connection list.

Each row shows the connection, its state, and its current rate. The actions menu beside each row controls the connection:

| Action | Effect |
| --- | --- |
| **Connection role** | `Primary` (weight 10), `Balanced` (weight 1), `Secondary` (0.3), `Backup` (0.05), or `Never` (excluded from the engine). |
| **Daily data limit** | Notifies you when the connection passes the limit for the day. |
| **Prefer this link** | Puts the connection first in the failover order. |
| **Test speed** | Measures that link alone. |

Connections sort with the active ones on top. When a device disconnects, the remaining links move up within a second, and a short animation plays showing the Mac and the device unlinking.

### Activity

Throughput over time, plus per-day usage for the last 30 days. **Export CSV** copies the history.

### Settings

Everything configurable lives on one tab: open at login, notifications, merging behaviour, adapter weighting, and the merge timeout. Developer mode is here too.

### Developer

Turn on **Settings → Developer** to reveal this tab. It adds engine diagnostics: raw status JSON, logs, adapter weights, include/exclude lists, tunneling options, the SOCKS5 proxy, and the Go profiler.

### Engine settings

Available on **Settings** and **Developer**:

| Setting | Options | Default |
| --- | --- | --- |
| Adapter weighting | `Auto` or `Manual` | `Auto` |
| Turn merging off after | Never, 30 minutes, 1 hour, 2 hours | Never |
| IPv6 | `auto`, `on`, `off` | `auto` |
| Tunnel MTU | 1500 (compatibility), 4096, 9000 (performance) | 1500 |
| Adapter rescan | 1 s, 3 s, 10 s | 1 s |
| Go profiler | on or off (`127.0.0.1:6060`) | off |

Changing IPv6, MTU, rescan, adapter inclusion, or weights restarts the engine. The supervisor brings it back with the new settings.

### Per-app proxy

Some apps should merge without the system-wide tunnel. **Developer → Per-app proxy (SOCKS5)** starts a local proxy on `127.0.0.1:1080` (configurable). Point an app at that address and it uses every included connection, while the rest of the system keeps its normal route. This mode needs no admin rights.

## How it works

LinkBlend is a front end. The networking is entirely `net-merge`.

```
LinkBlend.app  ──writes config──▶  /usr/local/var/linkblend/
      │                                    │
      │ sudo -n (sudoers rule)             │ reads
      ▼                                    ▼
/usr/local/bin/linkblend-supervisor ──starts──▶ net-merge run
      │                                              │
      │ writes                                       │ writes
      ▼                                              ▼
/var/log/linkblend.log                  /var/run/net-merge/status.json
                                                        │
                              LinkBlend reads status ◀──┘
```

**Three processes.** The app runs as you. The supervisor runs as root, because `net-merge` needs root to create its virtual adapter. `net-merge` runs as root under the supervisor. The app never performs privileged networking itself; it writes config files and reads the engine's status JSON once a second.

**Why the supervisor exists.** `net-merge` cannot change its adapter list without closing its tunnel, and closing the tunnel breaks every connection. So the supervisor starts it once with a superset list: the configured candidates plus `en0`–`en16` and `feth0`–`feth4`, minus any exclusions. `net-merge` filters that list by name and probes each adapter for a default route, so names that do not exist cost nothing. An adapter plugged in later joins on the next rescan, and the tunnel is never rebuilt because hardware came or went.

**How links are turned on and off.** The app uses `networksetup` to disable or enable the macOS network service. That changes interface addresses only, leaving the tunnel and the remaining links untouched. Pausing is the same operation applied to every link except one.

**Files it manages.**

| Path | Owner | Purpose |
| --- | --- | --- |
| `/usr/local/bin/linkblend-supervisor` | root | Supervisor script |
| `/usr/local/var/linkblend/*.conf` | you | Engine configuration |
| `/var/log/linkblend.log` | root | Supervisor log |
| `/var/log/linkblend-run.log` | root | Engine log |
| `/var/run/net-merge/status.json` | root | Live engine status |
| `~/Library/Application Support/LinkBlend/usage.json` | you | 30-day usage history |
| `~/Library/LaunchAgents/local.linkblend.plist` | you | Login item |

## Project layout

```
Sources/
  App/          LinkBlendApp.swift       app entry point, scenes, menu bar
                ContentView.swift        window shell, tabs, toasts
  Model/        LinkModel.swift          engine state and the polling loop
                LinkModel+Discovery      adapters, reachability, duplicate routes
                LinkModel+Stages         join stages, ordering, link events
                LinkModel+Connections    turning links on and off
                LinkModel+EngineSettings config files the supervisor reads
                LinkModel+Usage          status text, rates, usage history
                LinkModel+Developer      diagnostics and engine tuning
                LinkModel+Socks          per-app SOCKS5 proxy
                LinkModel+Notifications  user notifications
                LinkModel+Process        process helpers
  Models/       LinkRow, EngineStatus, Session value types
  Services/     Autostart.swift          login item
  Support/      Brand.swift              colours
                Formatting.swift         rate and byte formatting
                Motion.swift             animations that respect reduce motion
  Views/        OverviewView, ActivityView, DeveloperView, SettingsView,
                MenuBarContentView, ConnectionRow, LinkMorphView,
                MergePromptSheet, ActionsMenuButton
                (SettingsView renders inside the main window, not a
                separate window)

Scripts/
  build.sh            compiles Sources/ and packages LinkBlend.app
  install.sh          one-time setup for a fresh machine
  update.sh           safe in-place update
  supervisor.sh       root supervisor installed by install.sh
  uninstall.sh        removes the app, login item, and user data

Resources/AppIcon.icns
```

There is no Xcode project. `Scripts/build.sh` compiles every file under
`Sources/` with `swiftc`, so adding a file needs no project change.

## Uninstall

`Scripts/uninstall.sh` stops the engine, removes the app and its login item,
and deletes the user data. The three root-owned pieces stay behind on purpose,
because deleting a sudoers rule as the user whose rule it is needs root; the
script prints the exact `sudo rm` commands for them.

`Scripts/build.sh` alone compiles and installs the app but does not create the root-side files. Use `Scripts/install.sh` on a new machine.

## Command line

The engine is a normal CLI tool, so you can inspect and drive it directly:

```bash
net-merge status        # on/off state, per-adapter load
net-merge list          # adapters it can see
net-merge off           # stop a running engine
```

`net-merge off` stops an engine started with `run`, which is what the supervisor uses. The supervisor restarts it within about two seconds, so this is a safe way to force a restart with new settings. Other subcommands, including `tray` and `on`, belong to net-merge's own tray app rather than to the supervisor's `run` engine.

## Troubleshooting

**Merging never starts.** Check `sudo -n /usr/local/bin/linkblend-supervisor /usr/local/var/linkblend` runs without a password prompt. If it fails, re-run `Scripts/install.sh` to rewrite the sudoers rule.

**A phone does not merge.** The macOS network service for it may be disabled, or the device may not have authorized the Mac. Unlock the phone, tap **Trust**, and turn on USB tethering or Personal Hotspot. LinkBlend shows a progress indicator with the current step while it waits.

**Two links show as "Same route as another connection."** They reach the internet through the same gateway or public address, so merging them adds no capacity. LinkBlend excludes the lower-priority one.

**Nothing improves.** Capacity only adds when the links use different paths. Wi-Fi and a phone on cellular usually do; Wi-Fi and Ethernet behind the same router do not.

## Notes and limits

- Apple Silicon and macOS 26 only. `Scripts/build.sh` sets `-target arm64-apple-macos26.0`.
- The app is ad-hoc signed (`codesign -s -`), so Gatekeeper warns on first launch. Right-click the app and choose **Open**, or build it yourself.
- True packet-level redundancy would need a relay server. LinkBlend provides role-based failover weights instead, which keeps throughput additive.
- The tunnel is system-wide by default. Use the SOCKS5 proxy for per-app control.

## License

MIT. See [LICENSE](LICENSE).

The bonding engine, [net-merge](https://github.com/rohit267/net-merge), is a separate project by [rohit267](https://github.com/rohit267), also MIT licensed. LinkBlend depends on it and does not include or modify it.
