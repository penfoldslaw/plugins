# plugins — Claude Code edge lighting

Samsung-style **edge lighting** for [Claude Code](https://claude.com/claude-code) on Windows. When Claude finishes or needs you, a glowing border pulses around the edges of **every monitor** and a small card appears in the corner, so you notice without watching the terminal.

| When | What you see |
|---|---|
| Claude finishes | green glow + card |
| Claude needs permission | amber glow + card, **repeated every 2 minutes** until you answer (up to 1 hour) |
| Claude is waiting for your input | quiet gray card (no glow), repeated every 30 minutes (up to 4 hours), skipped while Windows Terminal is in front |

- Works on all monitors, DPI-aware, click-through glow, cards stack when several arrive at once, click a card to dismiss it.
- Never steals focus, never appears in the taskbar or Alt+Tab, never makes a sound.
- Shows the **session name** (your `/rename` title, else Claude Code's own title, else the folder name), so you know which session wants you.
- Also sends a silent Windows notification, so everything is kept in Notification Center history.
- No network access, no telemetry. Logging is off by default.

<!-- TODO: add a screenshot or short GIF at docs/demo.png -->

## Requirements

- Windows 10 or 11 with the built-in Windows PowerShell 5.1
- Claude Code
- Optional: the [BurntToast](https://github.com/Windos/BurntToast) module for the Notification Center entry. Without it you still get the glow and the cards.
  ```powershell
  Install-Module BurntToast -Scope CurrentUser
  ```

## Install

In Claude Code, add this repo as a plugin marketplace and install the plugin.

From GitHub:

```
/plugin marketplace add penfoldslaw/plugins
/plugin install edge-lighting@claude-edge-lighting
```

Or from a local clone, on any machine:

```
git clone https://github.com/penfoldslaw/plugins
```
```
/plugin marketplace add C:/path/to/plugins
/plugin install edge-lighting@claude-edge-lighting
```

The same two commands work from a normal terminal as `claude plugin marketplace add ...` and `claude plugin install ...`. Start a new Claude Code session afterwards so the hooks load.

Update later with `claude plugin update edge-lighting@claude-edge-lighting`. Uninstall with `claude plugin uninstall edge-lighting@claude-edge-lighting`.

> **If you already have your own notification hooks** in `settings.json`, remove them first. Plugin hooks run in addition to yours, so you would get everything twice.

## Try it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin folder>\scripts\test.ps1"
```

This shows green, amber and gray in turn. Inside Claude Code, the bundled `edge-lighting` skill can also run it and change settings for you (ask "change the edge-lighting idle reminder to 10 minutes").

## Configure

Optional. Create `%USERPROFILE%\.claude\edge-lighting\config.json` (see [`config.example.json`](plugins/edge-lighting/config.example.json)). Missing keys use the defaults. Changes apply to the next notification.

```json
{
  "colors": { "done": "#22C55E", "permission": "#F59E0B", "idle": "#9CA3AF" },
  "idle": { "mode": "popup", "intervalMinutes": 30, "maxHours": 4 },
  "permission": { "intervalMinutes": 2, "maxHours": 1, "repeatPulses": 2 },
  "card": { "holdSeconds": 6 },
  "edgeFlash": true, "cornerCard": true, "toast": true,
  "log": false
}
```

- `idle.mode: "none"` turns off idle notifications and their reminders entirely.
- `log: true` writes every hook payload and reminder event to `hook-log.jsonl` in the same folder. It contains your project paths and Claude's messages, so keep it off unless you are debugging.

## How it works

Claude Code hooks call small PowerShell scripts:

| Hook | Script | Job |
|---|---|---|
| `Stop` | `notify.ps1` | green glow + card; ends any permission reminder |
| `Notification` | `notify.ps1` | tells permission prompts from idle reminders using `notification_type` (falling back to the message text), shows the right visuals, starts the reminder loop |
| `UserPromptSubmit` | `clear-reminders.ps1` | you replied, so stop all reminders for that session |
| `PostToolUse` | `clear-permission.cmd` | a tool ran, so the permission was answered; stops that reminder. Runs after every tool call, so it first checks with plain `cmd` (about 30 ms) whether any permission reminder is active and only then starts PowerShell |

Reminders are hidden background PowerShell loops, one per kind and session, tracked by a marker file in `%USERPROFILE%\.claude\edge-lighting\state`. Deleting the marker stops the loop. Everything the hooks launch is detached, so hooks return immediately and never slow Claude down.

## GitHub Copilot CLI

The same scripts work with GitHub Copilot CLI, which has a similar hook system. From a clone of this repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File copilot\install.ps1
```

This writes `~/.copilot/hooks/edge-lighting.json` (every repo, honours `COPILOT_HOME`) pointing at the scripts in your clone, so keep the folder where it is. Restart Copilot CLI. Remove with `copilot\install.ps1 -Uninstall`. Settings are shared with the Claude Code plugin (`%USERPROFILE%\.claude\edge-lighting\config.json`).

- Green glow when the agent stops, amber glow + repeating reminder on permission prompts and elicitation dialogs, reminders cleared when you reply or a tool runs.
- The popup title uses the folder name (Copilot does not expose a session title).
- Not wired up: the idle reminder (Copilot's `agent_idle` event is not mapped yet).
- Written from GitHub's hooks reference and tested with simulated payloads only, not yet in a live Copilot CLI session. Reports welcome.
- If you use both tools, Copilot also reads `.claude/settings.json` hooks, so do not install both ways in the same repo or you may get duplicates.

## Limitations

- Windows only.
- If you interrupt a permission prompt with Esc, no hook fires, so the amber reminder continues until you type something, the turn ends, or the 1-hour limit.
- The idle reminder is skipped whenever Windows Terminal is the foreground window, even if the waiting session is in a different tab. The permission reminder is never skipped.
- Tested on Windows 11 with two monitors. Other layouts and DPI mixes should work but have had less testing, so issues and screenshots are welcome.

## Troubleshooting

Set `"log": true`, trigger the event, and read `%USERPROFILE%\.claude\edge-lighting\hook-log.jsonl`. No entry means the hook did not run (check `/plugin` that it is enabled and restart the session). If a reminder will not start or stop, delete the files in the `state` folder.

## License

MIT, see [LICENSE](LICENSE).
