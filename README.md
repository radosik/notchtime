# NotchTime

A tiny time tracker that lives in the MacBook notch. Hover the notch → the island opens;
name the task, pick the client, hit **Start**. The elapsed time sits beside the notch while
you work. Stop whenever you want — the timer never stops on its own (sleep, lid closed,
app relaunch: it keeps counting from the start time).

- Clients and projects, each client with its own hourly rate
- "Started 14:47 ✎" while running → type the hour it should really count from
- History window: per-day totals, edit date / start / end of any entry, continue a task
- **Export this month** → `.xlsx` summary report (merged descriptions, per-client totals, red grand total)
- No Dock icon, no menu bar icon. Quit from the island's `⋯` menu.

## Install

1. Download `NotchTime.dmg` from the latest [release](../../releases).
2. Drag **NotchTime** to **Applications**, then open it.
3. First launch only — the app is not notarized (no paid Apple developer account), so macOS will
   refuse it once. Go to **System Settings → Privacy & Security**, scroll down, click
   **Open Anyway**, then launch again. (Terminal alternative:
   `xattr -dr com.apple.quarantine /Applications/NotchTime.app`.)
4. Hover the notch.

Data is stored in `~/Library/Application Support/NotchTime/data.json`.

## Build locally

```
swift build -c release
scripts/package.sh      # → dist/NotchTime.app and dist/NotchTime.dmg
```

Releases are built by GitHub Actions on push of a `v*` tag.
