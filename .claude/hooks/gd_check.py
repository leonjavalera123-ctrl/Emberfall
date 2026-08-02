"""PostToolUse hook: parse-check any .gd file Claude just wrote.

Godot's --check-only exits 1 and prints "Parse Error" on a bad file, 0 when
clean (verified 2026-08-01). Exiting 2 here feeds stderr back to Claude so the
mistake is corrected in the same turn instead of surfacing minutes later when
the harness runs.
"""
import json
import os
import subprocess
import sys

GODOT = os.path.expandvars(
    r"%LOCALAPPDATA%\Microsoft\WinGet\Packages"
    r"\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
    r"\Godot_v4.7.1-stable_win64_console.exe"
)
PROJECT = os.path.join(os.path.dirname(__file__), "..", "..", "godot")


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0  # never block on a malformed payload

    path = (payload.get("tool_input") or {}).get("file_path") or ""
    if not path.endswith(".gd"):
        return 0

    project = os.path.abspath(PROJECT)
    full = os.path.abspath(path)
    if not full.startswith(project):
        return 0  # a .gd outside this project isn't ours to check

    if not os.path.exists(GODOT):
        return 0  # engine moved; stay out of the way rather than block every edit

    res_path = "res://" + os.path.relpath(full, project).replace(os.sep, "/")
    try:
        proc = subprocess.run(
            [GODOT, "--headless", "--path", project, "--check-only",
             "--script", res_path],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return 0

    if proc.returncode != 0:
        blob = (proc.stdout or "") + (proc.stderr or "")
        lines = [ln for ln in blob.splitlines()
                 if "error" in ln.lower() or "parse" in ln.lower()]
        print(f"GDScript parse check FAILED for {res_path}:", file=sys.stderr)
        print("\n".join(lines[:12]) or blob[-800:], file=sys.stderr)
        print("\nFix the syntax error before continuing.", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
