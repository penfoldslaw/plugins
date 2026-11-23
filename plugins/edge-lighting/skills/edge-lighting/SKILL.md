---
name: edge-lighting
description: Configure, test, or troubleshoot the edge-lighting notifications (screen-edge glow, corner cards, idle and permission reminders). Use when the user wants to change colours or reminder intervals, turn idle reminders off, enable logging, run a visual test, or figure out why a notification did not appear.
---

# edge-lighting

This plugin reacts to Claude Code hooks on Windows:

| Event | What the user sees |
|---|---|
| Claude finishes (`Stop`) | green edge glow + corner card + silent toast |
| Permission prompt (`Notification`) | amber edge glow + corner card + silent toast, repeated every few minutes until answered |
| Waiting for input (`Notification`, idle) | quiet gray corner card + toast, repeated every 30 minutes (skipped while Windows Terminal is in front); no glow |

Reminders stop when the user replies, a tool runs (permission answered), or the turn ends.

## Settings

Settings live in `%USERPROFILE%\.claude\edge-lighting\config.json`. The file is optional: missing keys use the defaults, and unknown keys or broken JSON are ignored. Copy `config.example.json` from the plugin folder as a starting point. Changes apply to the next notification, with no restart.

| Key | Default | Meaning |
|---|---|---|
| `log` | `false` | write hook payloads and reminder events to `hook-log.jsonl` in the same folder |
| `edgeFlash` / `cornerCard` / `toast` | `true` | switch each visual on or off |
| `colors.done` / `permission` / `idle` | `#22C55E` / `#F59E0B` / `#9CA3AF` | hex colours |
| `idle.mode` | `popup` | `popup` or `none` (no idle notification or reminder at all) |
| `idle.intervalMinutes` / `idle.maxHours` | `30` / `4` | idle reminder spacing and hard stop |
| `permission.intervalMinutes` / `maxHours` / `repeatPulses` | `2` / `1` / `2` | permission repeat spacing, hard stop, glow pulses |
| `card.holdSeconds` | `6` | how long a corner card stays |

When asked to change a setting, read the existing `config.json` if there is one, edit only the requested keys, and write it back as valid JSON.

## Test

Run the visual test (shows green, amber and gray, about 8 seconds each; add `-Case done|permission|idle` for one):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}/../../scripts/test.ps1"
```

## Troubleshooting

- **No toast, but glow and card work:** the optional BurntToast module is missing. `Install-Module BurntToast -Scope CurrentUser`.
- **Nothing at all:** set `"log": true`, trigger the event, and read `hook-log.jsonl`. No entry means the hook did not run (check the plugin is enabled with `/plugin`); an entry means the script ran, so look at the fields.
- **Everything appears twice:** the same hooks also exist in the user's own `settings.json`. Remove the duplicates there; plugin and user hooks both run.
- **A reminder will not stop or will not start:** delete the files in `%USERPROFILE%\.claude\edge-lighting\state\` (stale reminder markers).
