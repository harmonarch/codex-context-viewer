# Codex Context Monitor

A native macOS app that shows context usage for the latest active Codex user session.

## What It Shows

- Current session name, workspace, and last update time
- Last request context usage as a percentage of the model window
- Last input tokens, cached input tokens, and total run tokens
- A main dashboard with a donut chart for Instructions, Skills, MCP, Files, Messages, Tool Calls, Tool Output, Reasoning, and Other
- Hover details and click-through drilldown for each chart section, including per-skill usage
- Session picker, top contributors, warnings, Reset Display Baseline, and Undo Display Baseline Reset controls
- Copy Session Summary, which copies a compact continuation summary to the clipboard
- Check for Updates, which checks the latest GitHub Release, downloads the DMG installer, and opens it
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
git tag v0.1.4
git push origin v0.1.4
```

Tag builds create a GitHub Release and upload the DMG.

## Notes

- The percentage uses Codex's own latest `token_count` event when available.
- Category details are estimates derived from the local session record, intended to show what is taking space.
- Sub-agent sessions are ignored by default so the menu follows the latest user-owned Codex session.
- Reset Display Baseline does not delete Codex transcripts, clear a live Codex conversation, or change Codex's actual context. It only changes the baseline used by this monitor when showing post-reset display totals.
- Copy Session Summary does not rewrite the active Codex conversation. It creates a clipboard summary that can be pasted into a new or existing session.
- Check for Updates downloads the latest GitHub Release DMG and opens the installer. It does not silently replace the running app.
- The menu bar percentage and Actual Context Used show the actual Codex context usage. Displayed Since Baseline shows only the amount added after this monitor's display baseline was reset.

## Actual Usage vs Displayed Since Baseline

Reset Display Baseline is only a local display control in this monitor.

- Actual Context Used: Codex's current session usage from the latest local token count.
- Displayed Since Baseline: the amount added after the monitor's display baseline was reset.
- Notifications use Actual Context Used, so a display baseline reset will not hide a session that is actually over the notification threshold.
- To truly stop carrying old context, start a new Codex session or use a Codex-supported compaction flow.
