"""Regression checks for hook state, gates and concurrency; no app data or Swift builds."""

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


def state_for(snapshot=None, *, touched=False, gate=None):
    snapshot = snapshot if snapshot is not None else {"Example.swift": "same"}
    return {"baseline": snapshot.copy(), "current": snapshot.copy(),
            "swift_touched": touched, "last_gate_pass": gate}


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
            harness.save_state(path, state_for(snapshot))
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
            harness.save_state(path, state_for({"Example.swift": "old"}))
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

    def test_state_read_errors_and_invalid_shapes_are_not_missing_state(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            path = Path(directory) / "state.json"
            self.assertIsNone(harness.load_state(path))
            invalid = ["{broken", "[]", json.dumps({}),
                       json.dumps({**state_for(), "current": []}),
                       json.dumps({**state_for(), "current": {"Example.swift": 42}}),
                       json.dumps({**state_for(), "swift_touched": "false"}),
                       json.dumps({**state_for(), "last_gate_pass": 42})]
            for value in invalid:
                with self.subTest(value=value):
                    path.write_text(value)
                    with self.assertRaises(RuntimeError):
                        harness.load_state(path)
                    self.assertEqual(path.read_text(), value)
            path.unlink()
            path.mkdir()
            with self.assertRaises(RuntimeError):
                harness.load_state(path)

    def test_corrupt_state_blocks_at_hook_boundary_without_overwriting(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            root = Path(directory)
            path = root / "state.json"
            path.write_text("{broken")
            output = io.StringIO()
            with (
                patch.object(harness, "git_root", return_value=root),
                patch.object(harness, "read_event", return_value={"session_id": "test"}),
                patch.object(harness, "state_path", return_value=path),
                patch.object(harness, "lint_command") as lint,
                patch.object(sys, "argv", [str(HARNESS_PATH), "stop"]),
                contextlib.redirect_stdout(output),
            ):
                self.assertEqual(harness.main(), 0)
            self.assertEqual(json.loads(output.getvalue())["decision"], "block")
            self.assertEqual(path.read_text(), "{broken")
            lint.assert_not_called()

    def test_missing_baseline_blocks_post_tool_and_stop(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            root = Path(directory)
            path = root / "state.json"
            for hook in (harness.post_tool_use, harness.stop):
                output = io.StringIO()
                with (
                    patch.object(harness, "swift_snapshot", return_value={"Example.swift": "new"}),
                    patch.object(harness, "lint_command") as lint,
                    patch.object(harness, "run") as run,
                    contextlib.redirect_stdout(output),
                ):
                    hook(root, {}, path)
                self.assertEqual(json.loads(output.getvalue())["decision"], "block")
                self.assertFalse(path.exists())
                lint.assert_not_called()
                run.assert_not_called()

    def test_session_start_then_read_only_needs_no_gates(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            root = Path(directory)
            path = root / "state.json"
            with (
                patch.object(harness, "swift_snapshot", return_value={"Example.swift": "same"}),
                patch.object(harness, "lint_command") as lint,
                patch.object(harness, "run") as run,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                harness.session_start(root, {}, path)
                harness.post_tool_use(root, {}, path)
                harness.stop(root, {}, path)
            lint.assert_not_called()
            run.assert_not_called()
            self.assertFalse(harness.load_state(path)["swift_touched"])

    def test_full_lint_failure_blocks_and_never_runs_fast(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            root = Path(directory)
            path = root / "state.json"
            snapshot = {"Example.swift": "same"}
            harness.save_state(path, state_for(snapshot, touched=True))
            output = io.StringIO()
            with (
                patch.object(harness, "swift_snapshot", return_value=snapshot),
                patch.object(harness, "lint_command", return_value=(1, "lint failure")),
                patch.object(harness, "run") as run,
                contextlib.redirect_stdout(output),
            ):
                harness.stop(root, {}, path)
            self.assertEqual(json.loads(output.getvalue())["decision"], "block")
            self.assertIsNone(harness.load_state(path)["last_gate_pass"])
            run.assert_not_called()

    def test_fast_failure_blocks_and_does_not_cache_pass(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            root = Path(directory)
            path = root / "state.json"
            snapshot = {"Example.swift": "same"}
            harness.save_state(path, state_for(snapshot, touched=True))
            output = io.StringIO()
            with (
                patch.object(harness, "swift_snapshot", return_value=snapshot),
                patch.object(harness, "lint_command", return_value=(0, "")),
                patch.object(harness, "run", return_value=subprocess.CompletedProcess([], 1, "test failure")) as run,
                contextlib.redirect_stdout(output),
            ):
                harness.stop(root, {}, path)
            self.assertEqual(json.loads(output.getvalue())["decision"], "block")
            self.assertIsNone(harness.load_state(path)["last_gate_pass"])
            run.assert_called_once_with([str(root / "verify.sh"), "fast"], cwd=root)

    def test_pass_is_cached_then_new_swift_content_requires_recheck(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            root = Path(directory)
            path = root / "state.json"
            snapshot = {"Example.swift": "same"}
            harness.save_state(path, state_for(snapshot, touched=True))
            with (
                patch.object(harness, "swift_snapshot", return_value=snapshot) as snapshots,
                patch.object(harness, "lint_command", return_value=(0, "")) as lint,
                patch.object(harness, "run", return_value=subprocess.CompletedProcess([], 0, "PASS")) as run,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                harness.stop(root, {}, path)
                self.assertEqual(harness.load_state(path)["last_gate_pass"], harness.gate_fingerprint(root, snapshot))
                harness.stop(root, {}, path)
                self.assertEqual(lint.call_count, 1)
                self.assertEqual(run.call_count, 1)
                snapshots.return_value = {"Example.swift": "new"}
                harness.stop(root, {}, path)
                self.assertEqual(lint.call_count, 2)
                self.assertEqual(run.call_count, 2)

    def test_verification_input_changes_invalidate_cached_pass(self):
        for filename in (".swiftlint.yml", "verify.sh"):
            with self.subTest(filename=filename), tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
                root = Path(directory)
                config = root / filename
                config.write_text("old")
                snapshot = {"Example.swift": "same"}
                path = root / "state.json"
                old_gate = harness.gate_fingerprint(root, snapshot)
                harness.save_state(path, state_for(snapshot, touched=True, gate=old_gate))
                config.write_text("new")
                with (
                    patch.object(harness, "swift_snapshot", return_value=snapshot),
                    patch.object(harness, "lint_command", return_value=(0, "")) as lint,
                    patch.object(harness, "run", return_value=subprocess.CompletedProcess([], 0, "PASS")) as run,
                    contextlib.redirect_stdout(io.StringIO()),
                ):
                    harness.stop(root, {}, path)
                lint.assert_called_once_with(root)
                run.assert_called_once_with([str(root / "verify.sh"), "fast"], cwd=root)
                self.assertNotEqual(harness.load_state(path)["last_gate_pass"], old_gate)

    def test_verification_input_creation_and_removal_change_fingerprint(self):
        with tempfile.TemporaryDirectory(prefix="countdown-hook-check-") as directory:
            root = Path(directory)
            snapshot = {"Example.swift": "same"}
            missing = harness.gate_fingerprint(root, snapshot)
            (root / "verify.sh").write_text("content")
            present = harness.gate_fingerprint(root, snapshot)
            self.assertNotEqual(missing, present)
            (root / "verify.sh").unlink()
            self.assertEqual(missing, harness.gate_fingerprint(root, snapshot))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        raise SystemExit(worker(sys.argv[2], sys.argv[3]))
    unittest.main()
