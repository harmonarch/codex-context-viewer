# Codex Context Monitor

A native macOS app that shows context usage for the latest active Codex user session.

## What It Shows

- Current session name, workspace, and last update time
- Last request context usage as a percentage of the model window
- Last input tokens, cached input tokens, and total run tokens
- A main dashboard with a donut chart for Instructions, Skills, MCP, Files, Messages, Tool Calls, Tool Output, Reasoning, and Other
- Hover details and click-through drilldown for each chart section, including per-skill usage
- Session picker, top contributors, warnings, Reset Display, and Undo Display Reset controls
- Copy Session Summary, which copies a compact continuation summary to the clipboard
- A menu bar summary for quick access

The app reads local Codex files from `~/.codex`. It does not send data anywhere.

## Run From Source

```sh
swift run CodexContextMonitor
```

## Build The App

```sh
./scripts/build_app.sh
open "build/Codex Context Monitor.app"
```

## Build The DMG

```sh
./scripts/build_dmg.sh
open dist/Codex-Context-Monitor.dmg
```

## GitHub Release

The `Build DMG` workflow can be run manually from GitHub Actions. It also runs
automatically for version tags:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Tag builds create a GitHub Release and upload the DMG.

## Notes

- The percentage uses Codex's own latest `token_count` event when available.
- Category details are estimates derived from the local session record, intended to show what is taking space.
- Sub-agent sessions are ignored by default so the menu follows the latest user-owned Codex session.
- Reset Display does not delete Codex transcripts or change Codex's internal model context. It resets this monitor's displayed baseline for the selected session.
- Copy Session Summary does not rewrite the active Codex conversation. It creates a clipboard summary that can be pasted into a new or existing session.
- The menu bar percentage shows the actual Codex context usage. Dashboard display totals can show the amount added after the display baseline was reset.
