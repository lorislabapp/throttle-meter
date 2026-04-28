# Throttle Meter

> An open-source Claude Code usage meter for macOS. Watch your 5-hour and weekly limits live in your menu bar so you never get cut off mid-session without warning.

**MIT-licensed. Buildable from source.** This is the entire app — no hidden Pro tier, no paywall, no telemetry, no signup.

A separate commercial product called **Throttle** layers Pro features (Exact mode that mirrors claude.ai's exact numbers via Safari, hour-of-day heatmap, top-projects breakdown, Sparkle auto-update, license activation) on top of a private fork. Throttle is at https://lorislab.fr/throttle. **Throttle Meter** (this repo) is and will remain free, with no Pro upsell.

## What it does

- Reads your Claude Code session files at `~/.claude/projects/<repo>/<session>.jsonl`
- Sums tokens consumed across rolling 5-hour and weekly windows
- Shows usage as a percentage in your menu bar, with progress bars in the dropdown
- Auto-calibrates from your observed peaks; manually adjustable in Settings
- Threshold notifications at 80% / 95%
- 7-day Calendar reminder for the next weekly reset (one-tap, optional)
- Stats tab: usage trend chart, model split + EUR cost extrapolation, share badge
- Hook-status panel — checks whether your `session-start-router.sh` and pre-compact hooks are installed (the hook scripts themselves are in `scripts/hooks/` and on disk at `~/.claude/hooks/`)
- Works fully offline — no telemetry, no network calls, no account

## What it does *not* do

- Modify any file in `~/.claude/`
- Connect to Anthropic, LorisLabs, or anyone else
- Track or log session content (only token counts and timestamps)

## Privacy

Everything stays on your Mac. The privacy claim is **auditable in this repo** — see `Throttle/Services/`, `Throttle/Parser/`, `Throttle/DataLayer/`. The only filesystem reads are `~/.claude/projects/` (recursive) and writes are to `~/Library/Application Support/com.lorislab.throttle.meter/` (local SQLite + logs).

## Throttle Meter (Free) vs Throttle (Commercial)

The two products share the local-math meter. **Throttle Meter** in this repo is the open-source, MIT version with everything you need to track Claude Code usage on macOS. **Throttle** (lorislab.fr/throttle) adds:

| | Throttle Meter (MIT, this repo) | Throttle (commercial) |
|---|:---:|:---:|
| Live menu-bar meter | ✅ | ✅ |
| 5h + weekly windows + calibration | ✅ | ✅ |
| Token-opt hooks status + scripts | ✅ | ✅ |
| Threshold notifications + Calendar reminder | ✅ | ✅ |
| Stats: trend chart, model split, share badge | ✅ | ✅ |
| Diagnostics export | ✅ | ✅ |
| Exact mode (mirrors claude.ai's actual numbers via Safari) | ❌ | ✅ |
| Hour-of-day heatmap, top-projects breakdown | ❌ | ✅ |
| Sparkle auto-update + signed/notarized DMG | ❌ | ✅ |
| Direct support | ❌ | ✅ |

If the Free version is enough for you, that's the design. If you want Exact mode + auto-update + support, Throttle is €19 one-time at https://lorislab.fr/throttle.

## Build

Requirements:

- macOS 14 (Sonoma) or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
git clone https://github.com/lorislabapp/throttle-meter.git
cd throttle-meter
xcodegen generate
open ThrottleMeter.xcodeproj
```

Or build from CLI:

```bash
xcodebuild -project ThrottleMeter.xcodeproj -scheme Throttle \
  -configuration Release -destination 'platform=macOS' build
```

The `.app` lands in `~/Library/Developer/Xcode/DerivedData/ThrottleMeter-*/Build/Products/Release/Throttle Meter.app`.

## Tests

```bash
xcodebuild test -project ThrottleMeter.xcodeproj -scheme Throttle \
  -destination 'platform=macOS'
```

Unit tests cover JSONL parsing, calibration math, database queries, and the cold-start scanner.

## Token-opt hooks

Throttle Meter detects whether you have the LorisLabs token-optimization hook scripts installed. The scripts themselves are in `scripts/hooks/` — POSIX shell, work on Linux too — and you wire them into your Claude Code config manually. They prune project-irrelevant memory before each session, which on a typical multi-project setup skips ~50–100 k tokens per week. The Stats tab's "tokens saved" number is computed from the hooks' own log.

To install:

```bash
cp scripts/hooks/session-start-router.sh ~/.claude/hooks/
cp scripts/hooks/pre-compact.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

To disable temporarily:

```bash
export CLAUDE_DISABLE_TOKOPT_HOOKS=1
```

## Architecture

Layered SwiftUI 6 + GRDB.swift app. One responsibility per file:

```
Throttle/
├── Models/         Codable + GRDB record types
├── Database/       Migrations, DatabaseManager, queries
├── Parser/         JSONL line parser, file parser, warning detector
├── DataLayer/      Cold-start scanner, FSEvents watcher, hourly sweeper, coordinator
├── Calibration/    Window math, calibration engine (auto/manual/anchor)
├── State/          @Observable AppState, UsageSnapshot
├── Services/       AppLogger, ClaudeCodePathProvider, login items, hook status, calendar
├── UI/MenuBar/     Menu bar label + dropdown
├── UI/FirstRun/    3-step welcome window
├── UI/Settings/    Inline panes (General, Calibration, Hooks, Privacy)
├── UI/Stats/       Usage trend, model split, share badge
└── UI/States/      Log viewer, empty states
```

## Identity

Built and signed by **Christine Martin** (LorisLabs).

- Apple Developer Team ID: `TDV6D5L785`
- Bundle ID: `com.lorislab.throttle.meter`

## License

[MIT](LICENSE) — do whatever you want with it. Attribution appreciated, not required.

## Contributing

PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Be excellent to each other ([Code of Conduct](CODE_OF_CONDUCT.md)).
