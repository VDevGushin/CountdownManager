"""Deterministic checks of the eval judge, fixtures and isolated execution."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("agent_evals", ROOT / "evals/run.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class AgentEvalChecks(unittest.TestCase):
    def setUp(self):
        self.case = {"allowed_changes": [], "required_reads": [], "required_checks": [], "oracle": None}
        self.events = [{"type": "turn.completed", "usage": {"input_tokens": 1}}]
        self.execution = {"exit_code": 0, "timed_out": False}

    def grade(self, **kwargs):
        defaults = dict(case=self.case, before={}, after={}, events=self.events, malformed=[],
                        execution=self.execution, final="Inspected; no changes.")
        defaults.update(kwargs)
        return runner.grade(**defaults)

    def test_success_requires_qualitative_review(self):
        self.assertEqual(self.grade()["status"], "REVIEW_REQUIRED")

    def test_empty_and_failed_runs_are_infrastructure_errors(self):
        for events in ([], [{"type": "turn.failed"}]):
            self.assertEqual(self.grade(events=events)["status"], "INFRA_ERROR")
        self.assertEqual(self.grade(execution={"exit_code": 0, "timed_out": True})["status"], "INFRA_ERROR")

    def test_retry_event_does_not_override_eventual_completion(self):
        events = [{"type": "error", "message": "retrying"}] + self.events
        self.assertEqual(self.grade(events=events)["status"], "REVIEW_REQUIRED")

    def test_review_detects_addition_removal_and_modification(self):
        for before, after in (({}, {"new.txt": "a"}), ({"old.txt": "a"}, {}),
                              ({"file.txt": "a"}, {"file.txt": "b"})):
            result = self.grade(before=before, after=after)
            self.assertEqual(result["status"], "FAIL")
            self.assertEqual(result["checks"][2]["pass"], False)

    def test_failed_or_merely_started_command_does_not_count(self):
        self.case["required_checks"] = ["core-checks"]
        item = {"id": "cmd", "type": "command_execution", "command": "./verify.sh fast", "exit_code": 1,
                "aggregated_output": "PASS unit: checks\n"}
        for stage in ("item.started", "item.completed"):
            self.assertEqual(self.grade(events=[{"type": stage, "item": item}] + self.events)["status"], "FAIL")
        item["exit_code"] = 0
        self.assertEqual(self.grade(events=[{"type": "item.completed", "item": item}] + self.events)["status"],
                         "REVIEW_REQUIRED")

    def test_final_answer_claim_cannot_replace_independent_oracle(self):
        self.case.update(oracle="readonly-hook", allowed_changes=["hook.py"])
        result = self.grade(before={"hook.py": "old"}, after={"hook.py": "new"},
                            final="All tests pass!", oracle={"exit_code": 1, "timed_out": False})
        self.assertEqual(result["status"], "FAIL")

    def test_equivalent_verification_routes_use_real_completed_results(self):
        self.case["required_checks"] = ["swiftlint", "core-checks", "ui-checks"]
        commands = [
            ("swiftlint lint --quiet", ""),
            ("swift run --build-system native -c release CoreChecks", "PASS unit: checks\n"),
            ("swift run --build-system native -c release UIChecks", "PASS UI state: checks\n"),
        ]
        events = [{"type": "item.completed", "item": {
            "id": str(i), "type": "command_execution", "command": command,
            "exit_code": 0, "aggregated_output": output}}
            for i, (command, output) in enumerate(commands)] + self.events
        self.assertEqual(self.grade(events=events)["status"], "REVIEW_REQUIRED")
        combined = {"command": "bash ./verify.sh fast", "exit_code": 0,
                    "aggregated_output": "PASS unit: checks\nPASS UI state: checks\n"}
        self.assertEqual(runner.verified_operations(combined), {"core-checks", "ui-checks"})

    def test_reading_or_echoing_test_paths_is_not_running_tests(self):
        output = "Ran 12 tests in 0.3s\n\nOK\n"
        for command in ("cat Tests/test_swift_harness.py", "git diff -- Tests/test_swift_harness.py",
                        "echo 'python3 Tests/test_swift_harness.py'",
                        "python3 -c 'print(\"Tests/test_swift_harness.py\")'"):
            self.assertNotIn("hook-tests", runner.verified_operations({
                "command": command, "exit_code": 0, "aggregated_output": output}))

    def test_python_test_run_requires_a_successful_test_summary(self):
        command = "SWIFT_HARNESS_PATH=HarnessFixture/swift_harness.py python3 -B Tests/test_swift_harness.py"
        for output in ("", "Ran 0 tests in 0.3s\n\nOK\n", "Ran 12 tests in 0.3s\n\nFAILED (failures=1)\n"):
            self.assertEqual(runner.verified_operations({"command": command, "exit_code": 0,
                                                       "aggregated_output": output}), set())
        self.assertEqual(runner.verified_operations({"command": command, "exit_code": 0,
                         "aggregated_output": "............\nRan 12 tests in 0.3s\n\nOK\n"}), {"hook-tests"})

    def test_shell_wrappers_assignments_and_multiline_commands_are_recognized(self):
        command = "/bin/zsh -lc 'cd /private/tmp && X=1 swift run CoreChecks\nswift run UIChecks'"
        self.assertEqual(runner.verification_invocations(command), {"core-checks", "ui-checks"})
        self.assertEqual(runner.verification_invocations("echo 'swift run CoreChecks; swift run UIChecks'"), set())

    def test_static_target_loop_is_verified_only_with_real_success_markers(self):
        command = "/bin/zsh -lc 'for target in CoreChecks UIChecks; do\nswift run -c release \"$target\" || exit 1\ndone'"
        complete = {"command": command, "exit_code": 0,
                    "aggregated_output": "PASS unit: checks\nPASS UI state: checks\n"}
        self.assertEqual(runner.verified_operations(complete), {"core-checks", "ui-checks"})
        self.assertEqual(runner.verified_operations({**complete, "aggregated_output": "PASS UI state: checks\n"}),
                         {"ui-checks"})
        self.assertEqual(runner.verified_operations({**complete, "exit_code": 1}), set())
        quoted = "echo 'for target in CoreChecks UIChecks; do swift run $target; done'"
        self.assertEqual(runner.verified_operations({**complete, "command": quoted}), set())

    def test_recheck_preserves_original_evidence_and_requires_rubric_review(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "original"
            source.mkdir()
            (source / runner.MARKER).touch()
            case = {"id": "sample", "allowed_changes": [], "required_reads": [],
                    "required_checks": ["core-checks", "ui-checks"], "oracle": None,
                    "rubric": [{"id": "quality", "requirement": "Inspect quality"}]}
            runner.write_json(source / "suite.json", {"version": 2, "cases": [case]})
            runner.write_json(source / "manifest.json", {"expected_runs": 1, "case_ids": ["sample"],
                              "repeat": 1, "runner_sha256": "old-judge"})
            result = source / "sample-1"
            result.mkdir()
            original = {"status": "FAIL", "checks": []}
            runner.write_json(result / "checks.json", original)
            runner.write_json(result / "before.json", {})
            runner.write_json(result / "after.json", {})
            runner.write_json(result / "execution.json", {"exit_code": 0, "timed_out": False})
            (result / "final.txt").write_text("Inspected")
            runner.write_json(result / "review.json", {"reviewer": None, "checks": [
                {"id": "quality", "pass": None, "evidence": ""}]})
            events = [{"type": "item.completed", "item": {
                "id": "cmd", "type": "command_execution", "command": "./verify.sh fast", "exit_code": 0,
                "aggregated_output": "PASS unit: checks\nPASS UI state: checks\n"}}, {"type": "turn.completed"}]
            (result / "trace.jsonl").write_text("\n".join(json.dumps(e) for e in events))
            output = root / "rechecked"
            with contextlib.redirect_stdout(io.StringIO()), patch.object(runner, "execute") as execute:
                runner.recheck(source, output)
            execute.assert_not_called()
            self.assertEqual(json.loads((result / "checks.json").read_text()), original)
            self.assertEqual(json.loads((output / "sample-1/checks.original.json").read_text()), original)
            self.assertEqual(json.loads((output / "summary.json").read_text())["status"], "REVIEW_REQUIRED")
            self.assertTrue(json.loads((output / "manifest.json").read_text())["execution_reused"])
            with self.assertRaises(ValueError):
                runner.recheck(source, source / "nested")

    def test_forbidden_verification_attempt_fails_even_when_the_command_fails(self):
        self.case["forbidden_checks"] = ["core-checks"]
        item = {"id": "cmd", "type": "command_execution", "command": "./verify.sh fast", "exit_code": 1}
        self.assertEqual(self.grade(events=[{"type": "item.completed", "item": item}] + self.events)["status"], "FAIL")

    def test_official_gui_and_build_routes_are_detected_for_negative_controls(self):
        self.case["forbidden_checks"] = ["real-ui", "xcui", "app-build"]
        for command in ("./verify.sh ui", "bash verify.sh capture /private/tmp/captures",
                        "./run-xcui-tests.sh", "xcodebuild test", "swift build", "swiftc main.swift"):
            with self.subTest(command=command):
                item = {"id": "cmd", "type": "command_execution", "command": command, "exit_code": 1}
                result = self.grade(events=[{"type": "item.completed", "item": item}] + self.events)
                self.assertEqual(result["status"], "FAIL")
        self.assertEqual(runner.verification_invocations("./verify.sh capture /private/tmp/captures"),
                         {"real-ui", "app-build"})

    def test_default_full_route_and_read_only_compiler_queries(self):
        self.assertEqual(runner.verification_invocations("./verify.sh"),
                         {"core-checks", "ui-checks", "real-ui", "app-build"})
        for command in ("xcodebuild -version", "xcodebuild -list", "xcodebuild -showBuildSettings",
                        "swiftc --version", "swiftc -h", "swiftc -print-target-info", "swift build --help"):
            with self.subTest(command=command):
                self.assertEqual(runner.verification_invocations(command), set())
        self.assertEqual(runner.verification_invocations("xcodebuild test"), {"xcui", "app-build"})

    def test_empty_answer_and_malformed_trace_fail(self):
        self.assertEqual(self.grade(final="")["status"], "FAIL")
        self.assertEqual(self.grade(malformed=[2])["status"], "FAIL")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.jsonl"
            path.write_text('{"type":"turn.completed"}\nnot json\n[]\n')
            events, malformed = runner.parse_trace(path)
            self.assertEqual(len(events), 1)
            self.assertEqual(malformed, [2, 3])

    def test_fixture_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source"
            for source in ("no match", "old old"):
                path.write_text(source)
                with self.assertRaises(ValueError):
                    runner.replace_once(path, "old", "new")
            path.write_text("old")
            runner.replace_once(path, "old", "new")
            self.assertEqual(path.read_text(), "new")

    def test_diff_describes_agent_edits_including_untracked_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "source").write_text("repaired\n")
            (root / "new").write_text("added\n")
            diff = runner.change_diff({"source": b"injected\n", "deleted": b"removed\n"},
                                      root, ["source", "new", "deleted"])
            self.assertIn("-injected", diff)
            self.assertIn("+repaired", diff)
            self.assertIn("+added", diff)
            self.assertIn("-removed", diff)

    def test_snapshot_tracks_symlinks_and_excludes_build_products(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "link").symlink_to("not-present")
            (root / "dir-link").symlink_to(root, target_is_directory=True)
            (root / "evals/artifacts/run").mkdir(parents=True)
            (root / "evals/artifacts/run/trace").write_text("ignored")
            (root / ".build").mkdir()
            (root / ".build/file").write_text("ignored")
            self.assertEqual(runner.snapshot(root), {"link": "symlink:not-present", "dir-link": "symlink:" + str(root)})

    def test_execute_preserves_timeout_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = runner.execute([sys.executable, "-c", "import time; print('started', flush=True); time.sleep(20)"],
                                    root, 0.2, root / "stdout", root / "stderr")
            self.assertTrue(result["timed_out"])
            self.assertIn("started", (root / "stdout").read_text())

    def test_summary_rejects_incomplete_rubric_and_missing_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / runner.MARKER).touch()
            runner.write_json(root / "manifest.json", {"expected_runs": 1, "case_ids": ["sample"], "repeat": 1})
            case = {"id": "sample", "rubric": [{"id": "a"}, {"id": "b"}]}
            runner.write_json(root / "suite.json", {"cases": [case]})
            with contextlib.redirect_stdout(io.StringIO()):
                runner.summary(root)
            self.assertEqual(json.loads((root / "summary.json").read_text())["status"], "INCOMPLETE")
            result = root / "sample-1"
            result.mkdir()
            runner.write_json(result / "checks.json", {"status": "REVIEW_REQUIRED", "checks": []})
            runner.write_json(result / "review.json", {"reviewer": "reviewer", "checks": [
                {"id": "a", "pass": True, "evidence": "final.txt"}]})
            with contextlib.redirect_stdout(io.StringIO()):
                runner.summary(root)
            self.assertEqual(json.loads((root / "summary.json").read_text())["status"], "REVIEW_REQUIRED")
            runner.write_json(result / "review.json", {"reviewer": "reviewer", "checks": [
                {"id": "a", "pass": True, "evidence": "final.txt"},
                {"id": "b", "pass": False, "evidence": "trace.jsonl: skipped check"}]})
            with contextlib.redirect_stdout(io.StringIO()):
                runner.summary(root)
            self.assertEqual(json.loads((root / "summary.json").read_text())["status"], "FAIL")
            self.assertEqual(json.loads((root / "summary.json").read_text())["runs"][0]["failed_checks"],
                             ["rubric:b"])

    def test_python_fixture_is_reproduced_and_immutable_oracle_detects_repair(self):
        case = next(c for c in runner.load_suite()["cases"] if c["id"] == "fix-readonly-hook")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            hook = root / ".codex/hooks/swift_harness.py"
            hook.parent.mkdir(parents=True)
            shutil.copy2(ROOT / ".codex/hooks/swift_harness.py", hook)
            original = hook.read_text()
            runner.inject(root, case["fixture"])
            self.assertEqual(runner.oracle(case, root, root)["exit_code"], 1)
            (root / runner.HOOK_FIXTURE).write_text(original)
            self.assertEqual(runner.oracle(case, root, root)["exit_code"], 0)
            self.assertEqual(hook.read_text(), original)

    def test_suite_has_seven_cases_and_each_fixture_applies_to_current_source(self):
        suite = runner.load_suite()
        self.assertEqual(len(suite["cases"]), 7)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in ("Sources/CountdownCore/Countdown.swift", ".codex/hooks/swift_harness.py",
                             "Sources/CountdownManager/TimerCompletionAlert.swift", "Sources/CountdownManager/Store.swift",
                             "README.md"):
                destination = root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / relative, destination)
            for case in suite["cases"]:
                runner.inject(root, case["fixture"])

    def test_swift_oracle_checks_actual_compiled_behaviour_before_and_after_injection(self):
        case = next(c for c in runner.load_suite()["cases"] if c["id"] == "fix-today-label")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Sources/CountdownCore/Countdown.swift"
            source.parent.mkdir(parents=True)
            shutil.copy2(ROOT / "Sources/CountdownCore/Countdown.swift", source)
            original = source.read_text()
            result = runner.oracle(case, root, root)
            self.assertEqual(result["phase"], "runtime", (root / "oracle-build.stderr").read_text())
            self.assertEqual(result["exit_code"], 0)
            runner.inject(root, case["fixture"])
            result = runner.oracle(case, root, root)
            self.assertEqual(result["phase"], "runtime")
            self.assertEqual(result["exit_code"], 1)
            self.assertIn("FAIL: 0", (root / "oracle.stderr").read_text())
            source.write_text(original)

    def test_local_end_to_end_preserves_artifacts_and_does_not_leak_graders(self):
        case = next(c for c in runner.load_suite()["cases"] if c["id"] == "evidence-limits")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / "local-cli"
            # A local protocol fixture, not an LLM run or quality result.
            fake.write_text('''#!/usr/bin/env python3
import json
from pathlib import Path
import sys
args = sys.argv
workspace = Path(args[args.index('-C') + 1])
assert not (workspace / 'evals').exists()
assert not (workspace / 'Tests/test_agent_evals.py').exists()
assert (workspace / 'AGENTS.md').exists()
sys.stdin.read()
answer = 'Local protocol fixture: not an evaluated model answer.'
Path(args[args.index('-o') + 1]).write_text(answer)
print(json.dumps({'type': 'item.completed', 'item': {'id': 'cmd-1', 'type': 'command_execution',
    'command': 'cat docs/VERIFICATION.md', 'exit_code': 0, 'aggregated_output': 'fixture'}}))
print(json.dumps({'type': 'item.completed', 'item': {'id': 'answer', 'type': 'agent_message', 'text': answer}}))
print(json.dumps({'type': 'turn.completed', 'usage': {'input_tokens': 1, 'output_tokens': 1}}))
''')
            fake.chmod(0o755)
            output = root / "case"
            args = SimpleNamespace(codex=str(fake), timeout=30, model="local-protocol-fixture", effort="high")
            with contextlib.redirect_stdout(io.StringIO()):
                runner.run_case(case, output, args)
            self.assertEqual(json.loads((output / "checks.json").read_text())["status"], "REVIEW_REQUIRED")
            self.assertIsNone(json.loads((output / "review.json").read_text())["reviewer"])
            self.assertEqual(json.loads((output / "execution.json").read_text())["exit_code"], 0)
            for name in ("trace.jsonl", "final.txt", "before.json", "after.json", "diff.patch", "prompt.txt"):
                self.assertTrue((output / name).is_file(), name)
            self.assertEqual(json.loads((output / "before.json").read_text()),
                             json.loads((output / "after.json").read_text()))


if __name__ == "__main__":
    unittest.main()
