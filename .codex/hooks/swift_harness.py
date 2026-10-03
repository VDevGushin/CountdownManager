#!/usr/bin/env python3
"""Codex lifecycle hooks for incremental SwiftLint and Swift completion gates."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any


def run(
    command: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def git_root() -> Path:
    result = run(["git", "rev-parse", "--show-toplevel"], cwd=Path.cwd())
    if result.returncode != 0:
        raise RuntimeError(result.stdout.strip() or "Not inside a Git repository.")
    return Path(result.stdout.strip()).resolve()


def read_event() -> dict[str, Any]:
    try:
        value = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return {}
    return value if isinstance(value, dict) else {}


def swift_snapshot(root: Path) -> dict[str, str]:
    result = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z", "--", "*.swift"],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())

    snapshot: dict[str, str] = {}
    for raw_path in result.stdout.split(b"\0"):
        if not raw_path:
            continue
        relative_path = raw_path.decode(errors="surrogateescape")
        absolute_path = root / relative_path
        if absolute_path.is_file():
            snapshot[relative_path] = hashlib.sha256(absolute_path.read_bytes()).hexdigest()
    return snapshot


def changed_paths(before: dict[str, str], after: dict[str, str]) -> list[str]:
    paths = set(before) | set(after)
    return sorted(path for path in paths if before.get(path) != after.get(path))


def state_path(root: Path, session_id: str) -> Path:
    git_path = run(
        ["git", "rev-parse", "--git-path", "codex-hook-state"], cwd=root
    ).stdout.strip()
    state_directory = Path(git_path)
    if not state_directory.is_absolute():
        state_directory = root / state_directory
    state_directory.mkdir(parents=True, exist_ok=True)
    token = hashlib.sha256(session_id.encode()).hexdigest()
    return state_directory / f"{token}.json"


def load_state(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None
    return value if isinstance(value, dict) else None


def save_state(path: Path, state: dict[str, Any]) -> None:
    temporary_path = path.with_suffix(".tmp")
    temporary_path.write_text(
        json.dumps(state, ensure_ascii=False, sort_keys=True), encoding="utf-8"
    )
    temporary_path.replace(path)


def swiftlint_path() -> str | None:
    discovered = shutil.which("swiftlint")
    if discovered:
        return discovered
    homebrew_path = Path("/opt/homebrew/bin/swiftlint")
    return str(homebrew_path) if homebrew_path.is_file() else None


def lint_command(root: Path, paths: list[str] | None = None) -> tuple[int, str]:
    executable = swiftlint_path()
    if executable is None:
        return (
            127,
            "SwiftLint is required. Install it with `brew install swiftlint` and retry.",
        )

    command = [
        executable,
        "lint",
        "--config",
        str(root / ".swiftlint.yml"),
        "--strict",
        "--no-cache",
        "--quiet",
    ]
    environment = os.environ.copy()
    if paths is not None:
        existing_paths = [path for path in paths if (root / path).is_file()]
        if not existing_paths:
            return 0, ""
        environment["SCRIPT_INPUT_FILE_COUNT"] = str(len(existing_paths))
        for index, path in enumerate(existing_paths):
            environment[f"SCRIPT_INPUT_FILE_{index}"] = str(root / path)
        command.append("--use-script-input-files")

    result = run(command, cwd=root, env=environment)
    return result.returncode, result.stdout.strip()


def snapshot_fingerprint(snapshot: dict[str, str]) -> str:
    payload = json.dumps(snapshot, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()


def failure(reason: str) -> None:
    print(json.dumps({"decision": "block", "reason": reason[-8000:]}))


def session_start(root: Path, event: dict[str, Any], path: Path) -> None:
    if load_state(path) is None:
        snapshot = swift_snapshot(root)
        save_state(
            path,
            {
                "baseline": snapshot,
                "current": snapshot,
                "swift_touched": False,
                "last_gate_pass": None,
            },
        )
    print("{}")


def post_tool_use(root: Path, event: dict[str, Any], path: Path) -> None:
    current = swift_snapshot(root)
    state = load_state(path)
    needs_initial_state = state is None
    if state is None:
        state = {
            "baseline": current,
            "current": current,
            "swift_touched": False,
            "last_gate_pass": None,
        }

    previous = state.get("current")
    if not isinstance(previous, dict):
        previous = current
    changed = changed_paths(previous, current)
    state["current"] = current

    if not changed:
        if needs_initial_state:
            save_state(path, state)
        return

    state["swift_touched"] = True
    state["last_gate_pass"] = None
    save_state(path, state)

    return_code, output = lint_command(root, changed)
    if return_code != 0:
        details = output or "SwiftLint failed without diagnostic output."
        failure(f"Quick SwiftLint failed after a Swift edit.\n{details}")


def stop(root: Path, event: dict[str, Any], path: Path) -> None:
    state = load_state(path)
    if state is None:
        print("{}")
        return

    current = swift_snapshot(root)
    previous = state.get("current")
    if isinstance(previous, dict) and changed_paths(previous, current):
        state["current"] = current
        state["swift_touched"] = True
        state["last_gate_pass"] = None
        save_state(path, state)

    if not state.get("swift_touched"):
        print("{}")
        return

    fingerprint = snapshot_fingerprint(current)
    if state.get("last_gate_pass") == fingerprint:
        print("{}")
        return

    return_code, output = lint_command(root)
    if return_code != 0:
        details = output or "SwiftLint failed without diagnostic output."
        failure(f"Full SwiftLint gate failed.\n{details}")
        return

    verification = run([str(root / "verify.sh"), "fast"], cwd=root)
    if verification.returncode != 0:
        details = verification.stdout.strip() or "verify.sh failed without output."
        failure(f"Swift regression gate `./verify.sh fast` failed.\n{details}")
        return

    state["current"] = current
    state["last_gate_pass"] = fingerprint
    save_state(path, state)
    print("{}")


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {
        "session-start",
        "post-tool-use",
        "stop",
    }:
        print("Usage: swift_harness.py session-start|post-tool-use|stop", file=sys.stderr)
        return 64

    try:
        root = git_root()
        event = read_event()
        session_id = str(event.get("session_id") or "unknown-session")
        path = state_path(root, session_id)

        # Serialize the complete read/modify/write cycle for this session.
        # Keep the lock file in place so waiting processes share the same inode.
        with path.with_suffix(".lock").open("a") as lock_file:
            fcntl.flock(lock_file, fcntl.LOCK_EX)
            if sys.argv[1] == "session-start":
                session_start(root, event, path)
            elif sys.argv[1] == "post-tool-use":
                post_tool_use(root, event, path)
            else:
                stop(root, event, path)
    except Exception as error:  # Hooks must return a useful gate failure, not a traceback.
        failure(f"Swift harness hook failed: {error}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
