"""PreToolUse hook: refuse scene/resource edits while Godot is running.

The Godot editor holds the open scene in memory and rewrites the whole .tscn
on save. If an agent edits that file on disk while the editor is open, the next
editor save silently discards the change. Paid MCP servers exist to solve this;
refusing the edit costs nothing and solves it completely.

Only .tscn/.tres/.godot files are guarded — .gd scripts are re-read from disk by
the editor and are safe to edit live.
"""
import json
import os
import subprocess
import sys

GUARDED = (".tscn", ".tres", ".godot")


def godot_processes() -> list[str]:
    """Names of running Godot processes, or [] if we can't tell."""
    try:
        proc = subprocess.run(
            ["tasklist", "/FO", "CSV", "/NH"],
            capture_output=True, text=True, timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    names = []
    for line in proc.stdout.splitlines():
        first = line.split('","')[0].lstrip('"')
        if first.lower().startswith("godot"):
            names.append(first)
    return names


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    path = (payload.get("tool_input") or {}).get("file_path") or ""
    if not path.endswith(GUARDED):
        return 0

    running = godot_processes()
    if not running:
        return 0

    print(
        f"BLOCKED: {os.path.basename(path)} is a Godot scene/resource file and "
        f"Godot is currently running ({', '.join(sorted(set(running)))}).\n\n"
        "The editor holds this scene in memory and will overwrite any on-disk "
        "edit the next time it saves.\n\n"
        "Ask Leon to close Godot, then retry. If that process is the running "
        "GAME rather than the editor, closing it is still the safe move.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
