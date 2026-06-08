# Claude Code Auto-Allow

Automatically approve **Claude Code desktop** permission prompts, so tool calls run
without you clicking "Allow."

This repo has **two** approaches:

1. **Headless hook (recommended)** — `auto_approve.py`, a Claude Code `PreToolUse`
   hook that approves tool calls *inside the Claude Code engine*. Works even when the
   window is **minimized, closed to the tray, unfocused, or the screen is locked**,
   because it never touches the screen.
2. **GUI clicker (legacy)** — `Auto-Allow.ps1`, a PowerShell watcher that finds and
   clicks the "Allow" button via Windows UI Automation. Only works while the Claude
   window is **active and visible**.

---

## Recommended: headless `PreToolUse` hook

Before any tool runs, Claude Code pipes a JSON description of the tool call to the
hook on stdin. `auto_approve.py` logs it and returns an `allow` decision, so the tool
proceeds with no prompt — no GUI, no clicking, no active window needed.

### Install

1. Ensure **Python** is on your PATH (`python --version`).
2. Merge this into `~/.claude/settings.json` (keep any existing keys):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "python \"C:\\Users\\YOU\\path\\to\\auto_approve.py\"" }
        ]
      }
    ]
  }
}
```

3. Start a **new** Claude Code session — every tool call is now auto-approved.

### Audit log

Every approval is appended to `~/.claude/auto_approve.log` with a timestamp, tool name,
working directory, and the command/file. This is your record of what ran, since there's
no prompt to see anymore.

### Verify

```bash
python auto_approve.py --selftest
```

### Why it beats the clicker

- Works with the window minimized, closed to the tray, unfocused, or the screen locked.
- No CPU polling and no "keep the monitor on" requirement.
- Deterministic — no UI-automation races or duplicate clicks.

> **Note:** a Claude Code **session must be running** for the hook to fire. If the app is
> fully closed there's nothing to approve — but then nothing is running anyway.

---

## Legacy: GUI clicker

A PowerShell watcher that clicks the "Allow" button. Superseded by the hook above, but
kept for reference / non-hook setups.

| File | Purpose |
|------|---------|
| `Auto-Allow.ps1` | The watcher script |
| `Start-Auto-Allow.cmd` | Double-click launcher (re-launches automatically if it crashes) |

Double-click **`Start-Auto-Allow.cmd`**, or run the script directly:

```powershell
.\Auto-Allow.ps1 -IntervalMs 1000
```

Stop it with **Ctrl+C**, or close the window.

### Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-IntervalMs` | `1000` | How often to poll for a prompt, in milliseconds |
| `-ProcessName` | `Claude` | Process name of the desktop app (without `.exe`) |
| `-Inspect` | — | Dump every button across all Claude windows and exit (debugging) |

### How it works

1. Enumerates Claude desktop windows via UI Automation.
2. Searches the accessibility tree for an enabled **"Allow once" / "Allow always"** button.
3. Clicks it, trying three methods: UIA `Invoke()` → direct mouse click → focus window + `Ctrl+Enter`.

### Limitation

Only the **active/visible** session's interface is reliably exposed to UI Automation, so
background tabs and a locked screen don't work — this is exactly why the hook is preferred.

---

## ⚠️ Disclaimer

Auto-approving permission prompts **removes a safety gate** — every tool call (including
file writes and shell commands) runs without review. Use only on machines and projects
where you understand and accept that risk. The audit log is your only after-the-fact record.
