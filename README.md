# Claude Code Auto-Allow

A small Windows utility that automatically approves **Claude Code desktop** permission prompts.

It watches Claude desktop windows using Windows **UI Automation** and clicks the
**"Allow once"** button whenever a permission prompt appears — so you don't have to
approve tool calls by hand.

## Files

| File | Purpose |
|------|---------|
| `Auto-Allow.ps1` | The watcher script |
| `Start-Auto-Allow.cmd` | Double-click launcher (re-launches automatically if it crashes) |

## Usage

Double-click **`Start-Auto-Allow.cmd`**, or run the script directly:

```powershell
.\Auto-Allow.ps1 -IntervalMs 10000
```

Stop it with **Ctrl+C**, or just close the window.

### Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-IntervalMs` | `10000` | How often to poll for a prompt, in milliseconds |
| `-ProcessName` | `Claude` | Process name of the desktop app (without `.exe`) |
| `-Inspect` | — | Dump every button across all Claude windows and exit (debugging) |

```powershell
# See what buttons are currently on screen (run with a prompt showing):
.\Auto-Allow.ps1 -Inspect
```

## How it works

1. Enumerates every Claude desktop window via UI Automation.
2. Searches the accessibility tree for an enabled **"Allow once" / "Allow always"** button.
3. Clicks it, trying three methods in order: UIA `Invoke()` → direct mouse click → focus window + `Ctrl+Enter`.

## Limitations

- Only the **active/visible** session's interface is reliably exposed to UI Automation.
  Background session tabs are not rendered, so their prompts can't be detected until you switch to them.
- Windows-only (relies on Windows UI Automation and PowerShell).

## ⚠️ Disclaimer

Auto-approving permission prompts **removes a safety gate** — every tool call (including
file writes and shell commands) is approved without review. Use only on machines and
projects where you understand and accept that risk.
