# macOS Accessibility-Based Content Blocker

A production-grade, self-control content blocker for macOS that prevents
access to adult websites. It combines two independent layers:

1. **Network layer (first line):** a root daemon mirrors a blocklist into
   `/etc/hosts`, so most known sites never load — in any browser, and
   regardless of whether a VPN is active.
2. **Accessibility layer (last line of defense):** a background
   LaunchAgent reads browser page content through the macOS Accessibility
   APIs, scores it for adult content, and closes the tab / window / browser
   when a threshold is crossed — catching arbitrary pages the hosts list
   doesn't know about.

No screenshots, no OCR, no screen recording, no keystroke logging.

> ⚠️ This is a self-control tool meant to be installed on *your own* Mac.
> It is intentionally hard (not impossible) to disable from the UI. The
> `uninstall.sh` script is the operator-level escape hatch.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ BlockerApp (SwiftUI)            user-facing dashboard               │
│   status · domains · activity · settings · delayed-disable          │
└───────────────┬────────────────────────────────────────────────────┘
                │ reads/writes JSON in Application Support
┌───────────────▼────────────────────────────────────────────────────┐
│ ~/Library/Application Support/PornBlocker                            │
│   config.json · state.json · blocklist-*.json · whitelist.json       │
│   events.log · blocked-domains.txt (export)                          │
└───────────────┬───────────────────────────────────┬─────────────────┘
                │                                     │ WatchPaths
┌───────────────▼─────────────────────┐  ┌────────────▼────────────────┐
│ blockerd  (user LaunchAgent)         │  │ hosts-sync (root LaunchDaemon)│
│  BlockerService                      │  │  rewrites managed block in    │
│   ├─ BrowserMonitor (AXObserver)     │  │  /etc/hosts, flushes DNS      │
│   ├─ DetectionEngine (scoring)       │  └───────────────────────────────┘
│   ├─ EnforcementEngine (tab→kill)    │
│   └─ VPNWatcher (NWPathMonitor)      │
└──────────────────────────────────────┘
```

`BlockerCore` is a shared library; `blockerd` and `BlockerApp` are thin
executables on top of it.

### Folder structure

```
macos-web-content-blocker/
├── Package.swift
├── README.md
├── Sources/
│   ├── BlockerCore/
│   │   ├── BlockerService.swift          orchestrator
│   │   ├── Config/                       Paths, AppConfig, StateStore
│   │   ├── Detection/                    DomainMatcher, KeywordLists,
│   │   │                                 PageSnapshot, DetectionEngine
│   │   ├── Blocklist/                    BlocklistStore + hosts export
│   │   ├── Accessibility/                AXHelpers, BrowserMonitor,
│   │   │                                 SupportedBrowsers, permissions
│   │   ├── Enforcement/                  EnforcementEngine
│   │   ├── VPN/                          VPNWatcher
│   │   ├── Logging/                      EventLogger
│   │   └── Security/                     TamperGuard
│   ├── blockerd/                         daemon entrypoint
│   └── BlockerApp/                       SwiftUI dashboard
├── LaunchAgents/                         plist templates
└── Scripts/                              install / uninstall / hosts-sync
```

---

## Detection engine

A confidence-scoring classifier over a `PageSnapshot` (title, URL,
headings, links, buttons, static text — all from the accessibility tree).

| Signal                              | Confidence | Points        |
|-------------------------------------|------------|---------------|
| Known adult domain (URL match)      | High       | +100          |
| Adult brand name in window title    | High       | +50           |
| Category keyword (word-boundary)    | Medium     | +30 (cap 90)  |
| Isolated keyword                    | Low        | +10 (cap 30)  |

**Block when `score >= threshold`** (default 100, tunable in Settings).
Whitelisted hosts always score 0. A cheap substring pre-filter skips the
full keyword pass when no relevant fragment appears anywhere in the page.

Word-boundary matching prevents false positives like "Sussex" → "sex" or
"analysis" → "anal".

---

## Enforcement (escalating)

```
Detected ─▶ Close tab (⌘W) ─▶ still blocked? ─▶ Close window
                                                     │
                                                     ▼
                                          still blocked? ─▶ Kill browser
```

Each enforcement also: adds the domain to the **runtime blocklist**
(which feeds the hosts export), records an event, and starts a
**cooldown** during which re-detecting the same domain escalates
straight to terminating the browser.

---

## Domain block system

Three blocklists + a whitelist:

- **Permanent** — compiled-in seed list of known adult domains.
- **Runtime** — auto-added by enforcement.
- **Custom** — user-added (supports `*.example.com` wildcards & subdomains).
- **Whitelist** — never blocked, overrides everything.

All blocked domains are exported to `blocked-domains.txt`; the root
hosts-sync daemon turns each into `0.0.0.0`/`::1` entries inside a marked
block in `/etc/hosts`, then flushes the DNS cache.

---

## VPN awareness

`VPNWatcher` uses `NWPathMonitor` to detect `utun`/`ipsec`/`ppp`/`wg`
interfaces. Because monitoring and enforcement are entirely
browser/accessibility-driven (not packet inspection), **a VPN changes
nothing** — detection and blocking continue. The watcher only updates
status for the dashboard.

---

## Performance

- Fully **event-driven**: `AXObserver` notifications + `NSWorkspace`
  app-launch/activate events. No polling loops in the daemon.
- A 0.35 s debounce coalesces notification bursts into a single scan.
- Tree walk is bounded (≤600 nodes, depth ≤14, capped text) to keep CPU
  and memory flat on huge pages.
- Targets <50 MB RAM and <2 % CPU at idle.

---

## Security / tamper resistance

- **Delayed disable:** turning protection off from the UI requires a
  request, a waiting period (default 24 h), then a second confirmation
  (`TamperGuard`).
- **KeepAlive** LaunchAgent: the daemon relaunches if killed.
- **Cooldown** periods escalate repeat offenders.

---

## Logging

Append-only JSON-lines log (`events.log`, auto-rotated at 5 MB). Each
event stores: timestamp, browser, trigger reason, domain, confidence
score, action taken. **Never** screenshots, page content, or keystrokes.

---

## Build & deploy

Requirements: macOS 14+, Swift 6 toolchain (Xcode 16+).

```bash
cd macos-web-content-blocker

# Build only
swift build -c release

# Install everything (builds, installs both services, starts daemon)
./Scripts/install.sh
```

Then grant Accessibility permission:

> System Settings ▸ Privacy & Security ▸ Accessibility → enable **blockerd**

The daemon begins monitoring the instant permission is granted. Launch
the dashboard from the path printed by the installer
(`.build/release/BlockerApp`).

> **Note on permissions:** running the daemon as a bare SwiftPM binary
> means the *binary* (`blockerd`) is what appears in the Accessibility
> list. For a hardened, code-signed distribution, wrap `blockerd` and
> `BlockerApp` into a signed `.app` bundle with the appropriate
> entitlements — the source is structured so that is a packaging step,
> not a code change.

### Uninstall

```bash
./Scripts/uninstall.sh
```

Stops both services, removes the plists, and strips the managed block
from `/etc/hosts`. Support data is left in place unless you delete it.

---

## Notes & limitations

- **Firefox** exposes its web content over accessibility only when
  `accessibility.force_disabled = 0` (the default once a screen reader /
  AX client is active). The hosts layer covers Firefox regardless.
- Chromium-family browsers expose the page URL via `AXWebArea`'s `AXURL`;
  Safari via the window's `AXDocument`. The engine falls back to
  title-only scoring when the URL isn't readable.
- The hosts layer can't express wildcards, so `*.example.com` entries are
  flattened to the apex domain there; the accessibility layer still
  catches arbitrary subdomains by content.
