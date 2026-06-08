#!/usr/bin/env python3
"""
auto_approve.py - headless auto-approver for Claude Code permission prompts.

Runs as a Claude Code *PreToolUse* hook. Before any tool runs, Claude Code
pipes a JSON blob to this script on stdin. This script logs the action and
immediately returns an "allow" decision, so the tool runs without any prompt -
no GUI, no clicking, no active window required. It works whether the Claude
window is focused, minimized, closed to the tray, or the screen is locked,
because it runs inside the Claude Code engine, not the UI.

Scope: approve EVERYTHING. Every approval is written to the log file so you
have an audit trail (this replaces the visual prompt you used to click).

Output contract (Claude Code PreToolUse):
    {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                            "permissionDecision": "allow"|"deny"|"ask",
                            "permissionDecisionReason": "..."}}

Safety: any internal error still emits a valid "allow" so a hook bug can never
wedge a running session. Run `python auto_approve.py --selftest` to verify
output + logging without Claude Code.
"""

import sys
import os
import json
from datetime import datetime
from pathlib import Path

LOG_PATH = str(Path.home() / ".claude" / "auto_approve.log")


def log(msg):
    line = f"[{datetime.now().isoformat(timespec='seconds')}] {msg}"
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def build_decision(reason):
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": reason,
        }
    }


def summarize(payload):
    """Return (tool, cwd, short_detail) for logging."""
    tool = payload.get("tool_name", "unknown")
    cwd = payload.get("cwd", "")
    ti = payload.get("tool_input", {}) or {}
    if tool == "Bash":
        detail = ti.get("command", "")
    elif tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        detail = "file: " + (ti.get("file_path") or ti.get("notebook_path") or "")
    else:
        try:
            detail = json.dumps(ti)[:300]
        except (TypeError, ValueError):
            detail = str(ti)[:300]
    return tool, cwd, detail


def emit_allow(reason):
    print(json.dumps(build_decision(reason)))
    sys.exit(0)


def main():
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, ValueError) as e:
        log(f"WARN could not parse stdin ({e}); approving anyway.")
        emit_allow("auto-approved (unparsed payload)")
        return

    try:
        tool, cwd, detail = summarize(payload)
        log(f"ALLOW {tool} | cwd={cwd} | {detail[:500]}")
        emit_allow(f"auto-approved: {tool}")
    except Exception as e:  # never let a hook crash wedge a session
        log(f"WARN error while handling payload ({e}); approving anyway.")
        emit_allow("auto-approved (handler error)")


def selftest():
    samples = [
        {"tool_name": "Bash", "tool_input": {"command": "rm -rf build/"}, "cwd": "C:\\proj"},
        {"tool_name": "Write", "tool_input": {"file_path": "C:\\proj\\App.java"}, "cwd": "C:\\proj"},
        {"tool_name": "mcp__some__tool", "tool_input": {"q": "x"}, "cwd": "C:\\proj"},
    ]
    print(f"Log file: {LOG_PATH}\n")
    for s in samples:
        tool, cwd, detail = summarize(s)
        log(f"SELFTEST ALLOW {tool} | cwd={cwd} | {detail[:500]}")
        print(f"{tool:>22}  ->  {json.dumps(build_decision('auto-approved: ' + tool))}")
    print("\nSelftest OK: all samples produced a valid 'allow' decision and a log line.")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        main()
