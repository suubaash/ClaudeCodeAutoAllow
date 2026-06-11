#!/usr/bin/env python3
"""
claude-auto-allow.py - scoped, fail-open auto-approver for Claude Code (PreToolUse hook).

Runs (via claude-auto-allow.cmd) as a GLOBAL PreToolUse hook, because the desktop app
only honors global hooks. It then decides BY FOLDER:

  - cwd is under an allowed folder (ALLOW_DIRS)  -> return "allow" (no prompt) + log it
  - anything else (fintech repo, etc.)           -> emit NOTHING -> Claude prompts normally

It NEVER exits non-zero and never blocks: any error or out-of-scope case just exits 0 with
no decision. The .cmd wrapper also forces exit 0. So a broken/missing hook can never wedge
a session. Add folders to ALLOW_DIRS to auto-approve them too.
"""

import sys
import json
from datetime import datetime
from pathlib import Path

LOG_PATH = str(Path.home() / ".claude" / "claude-auto-allow.log")

# Auto-approve only when the working dir contains one of these (normalized: lowercase, backslashes).
ALLOW_DIRS = [r"\gmepay+"]


def log(msg):
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(f"[{datetime.now().isoformat(timespec='seconds')}] {msg}\n")
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


def cwd_allowed(cwd):
    n = (cwd or "").replace("/", "\\").lower()
    return any(d in n for d in ALLOW_DIRS)


def summarize(payload):
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


def decide(payload):
    """Return a decision dict to print, or None to do nothing (normal prompt)."""
    tool, cwd, detail = summarize(payload)
    if cwd_allowed(cwd):
        log(f"ALLOW {tool} | cwd={cwd} | {detail[:500]}")
        return build_decision(f"auto-approved (GMEPay+): {tool}")
    return None


def main():
    try:
        raw = sys.stdin.read() or ""
        # strip any BOM (utf-8-sig) and surrounding whitespace, then parse
        raw = raw.encode("utf-8", "ignore").decode("utf-8-sig", "ignore").strip()
        payload = json.loads(raw) if raw else {}
        decision = decide(payload)
        if decision is not None:
            print(json.dumps(decision))
    except Exception as e:  # never block - swallow everything, emit no decision
        try:
            log(f"WARN handler error ({e}); no-op (normal prompt).")
        except Exception:
            pass
    sys.exit(0)


def selftest():
    cases = [
        ("GMEPay+ \\code (ALLOW)",          {"tool_name": "Bash",  "tool_input": {"command": "./gradlew build"}, "cwd": "C:\\Users\\GME\\.claude\\GMEPay+\\code"}),
        ("GMEPay+ \\Documentation (ALLOW)", {"tool_name": "Write", "tool_input": {"file_path": "a.md"},          "cwd": "C:\\Users\\GME\\.claude\\GMEPay+\\Documentation"}),
        ("GMEPay+ bash-path (ALLOW)",       {"tool_name": "Bash",  "tool_input": {"command": "ls"},              "cwd": "/c/Users/GME/.claude/GMEPay+/code"}),
        ("fintech remit_platform (no-op)",  {"tool_name": "Bash",  "tool_input": {"command": "rm -rf build"},    "cwd": "C:\\Users\\GME\\Projects\\remit_platform"}),
        ("this Claude Plugin (no-op)",      {"tool_name": "Bash",  "tool_input": {"command": "ls"},              "cwd": "C:\\Users\\GME\\.claude\\Claude Plugin"}),
    ]
    print("Scope test (ALLOW only for GMEPay+):")
    for label, payload in cases:
        d = decide(payload)
        print(f"  {label:34} -> {'ALLOW' if d else 'no-op (normal prompt)'}")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        main()
