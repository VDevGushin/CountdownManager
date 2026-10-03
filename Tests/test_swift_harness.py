"""Regression checks for hook concurrency; no application data or Swift builds."""

import contextlib
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HARNESS_PATH = Path(os.environ.get(
    "SWIFT_HARNESS_PATH",
    str(Path(__file__).resolve().parents[1] / ".codex/hooks/swift_harness.py"),
))
spec = importlib.util.spec_from_file_location("swift_harness", HARNESS_PATH)
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


def worker(root, stage):
    root = Path(root)
    original_replace = Path.replace

    def slow_replace(path, target):
        # Widen the original shared-temporary-file race deterministically.
        time.sleep(0.03)
        return original_replace(path, target)

    with (
        patch.object(harness, "git_root", return_value=root),
        patch.object(harness, "read_event", return_value={"session_id": "concurrent"}),
        patch.object(harness, "state_path", return_value=root / "state.json"),
        patch.object(harness, "swift_snapshot", return_value={"Example.swift": "new"}),
        patch.object(harness, "lint_command", return_value=(0, "")),
        patch.object(harness, "run", return_value=subprocess.CompletedProcess([], 0, "")),
        patch.object(Path, "replace", slow_replace),
        patch.object(sys, "argv", [str(HARNESS_PATH), stage]),
    ):
        return harness.main()


class SwiftHarnessChecks(unittest.TestCase):
    def test_parallel_lifecycle_calls_preserve_state(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            root = Path(directory)
            harness.save_state(root / "state.json", {
                "baseline": {"Example.swift": "old"},
                "current": {"Example.swift": "old"},
                "swift_touched": False,
                "last_gate_pass": None,
            })

            def launch(stage):
                return subprocess.run(
                    [sys.executable, str(Path(__file__).resolve()), "--worker", directory, stage],
                    capture_output=True, text=True, timeout=15,
                )

            stages = ["post-tool-use", "session-start", "stop"] * 8
            with ThreadPoolExecutor(max_workers=12) as pool:
                results = list(pool.map(launch, stages))
            for result in results:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('"decision": "block"', result.stdout, result.stdout)
            state = harness.load_state(root / "state.json")
            self.assertTrue(state["swift_touched"])
            self.assertEqual(state["baseline"], {"Example.swift": "old"})
            self.assertEqual(state["current"], {"Example.swift": "new"})
            self.assertFalse((root / "state.tmp").exists())

    def test_read_only_call_does_not_run_lint(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            root = Path(directory)
            path = root / "state.json"
            snapshot = {"Example.swift": "same"}
            harness.save_state(path, {"current": snapshot, "swift_touched": False})
            with (
                patch.object(harness, "swift_snapshot", return_value=snapshot),
                patch.object(harness, "lint_command") as lint,
                patch.object(harness, "save_state") as save,
            ):
                harness.post_tool_use(root, {}, path)
            lint.assert_not_called()
            save.assert_not_called()
            self.assertFalse(harness.load_state(path)["swift_touched"])

    def test_swift_edit_still_blocks_on_lint_failure(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            root = Path(directory)
            path = root / "state.json"
            harness.save_state(path, {"current": {"Example.swift": "old"}})
            output = io.StringIO()
            with (
                patch.object(harness, "swift_snapshot", return_value={"Example.swift": "new"}),
                patch.object(harness, "lint_command", return_value=(1, "lint rejected")) as lint,
                contextlib.redirect_stdout(output),
            ):
                harness.post_tool_use(root, {}, path)
            lint.assert_called_once_with(root, ["Example.swift"])
            self.assertEqual(json.loads(output.getvalue())["decision"], "block")
            self.assertTrue(harness.load_state(path)["swift_touched"])


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        raise SystemExit(worker(sys.argv[2], sys.argv[3]))
    unittest.main()
