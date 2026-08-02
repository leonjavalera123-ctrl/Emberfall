"""Stop hook: the turn cannot end with a red selftest.

Runs Emberfall's own harness. To stay cheap on conversational turns it hashes
the project's source files and skips the run when nothing has changed since the
last green result, so the selftest only fires when code actually moved.

The harness needs a GPU to render its screenshot and measure FPS, so it opens a
real window for ~20s. That is the cost of the gate. To disable temporarily,
comment out the Stop hook in .claude/settings.json.
"""
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", "godot"))
STATE = os.path.join(HERE, "..", ".selftest_state")
SHOT = os.path.join(PROJECT, "_stophook.png")  # gitignored: /godot/*.png

GODOT = os.path.expandvars(
    r"%LOCALAPPDATA%\Microsoft\WinGet\Packages"
    r"\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
    r"\Godot_v4.7.1-stable_win64_console.exe"
)
SOURCE_EXT = (".gd", ".tscn", ".tres", ".gdshader")


def source_hash() -> str:
    """Hash every source file, ignoring vendored addons."""
    digest = hashlib.sha256()
    for root, dirs, files in os.walk(PROJECT):
        dirs[:] = [d for d in dirs if d not in (".godot", "addons")]
        for name in sorted(files):
            if name.endswith(SOURCE_EXT):
                path = os.path.join(root, name)
                digest.update(name.encode())
                try:
                    with open(path, "rb") as handle:
                        digest.update(handle.read())
                except OSError:
                    pass
    return digest.hexdigest()


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    # Claude Code sets this when the turn was already continued by a Stop hook.
    # Without this guard a persistently failing selftest loops forever.
    if payload.get("stop_hook_active"):
        return 0

    if not os.path.exists(GODOT):
        return 0

    current = source_hash()
    try:
        with open(STATE) as handle:
            if handle.read().strip() == current:
                return 0  # nothing changed since the last green run
    except OSError:
        pass

    try:
        proc = subprocess.run(
            [GODOT, "--path", PROJECT, "--", "--selftest", SHOT],
            capture_output=True, text=True, timeout=300,
        )
    except subprocess.TimeoutExpired:
        print("Selftest TIMED OUT after 300s — the game did not exit.",
              file=sys.stderr)
        return 2
    finally:
        for stray in (SHOT, SHOT + ".import"):
            try:
                os.remove(stray)
            except OSError:
                pass

    blob = (proc.stdout or "") + (proc.stderr or "")
    script_errors = [ln for ln in blob.splitlines() if "SCRIPT ERROR" in ln]
    got_fps = "selftest avg fps" in blob

    if proc.returncode != 0 or script_errors or not got_fps:
        print("SELFTEST FAILED — do not end the turn here.", file=sys.stderr)
        print(f"exit={proc.returncode} fps_line={got_fps} "
              f"script_errors={len(script_errors)}", file=sys.stderr)
        for line in (script_errors or blob.splitlines())[:15]:
            print("  " + line, file=sys.stderr)
        return 2

    with open(STATE, "w") as handle:
        handle.write(current)

    fps = next((ln for ln in blob.splitlines() if "selftest avg fps" in ln), "")
    print(f"Selftest green. {fps.strip()}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
