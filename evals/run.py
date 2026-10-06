#!/usr/bin/env python3
"""Small, evidence-first Codex eval runner. Standard library only."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import difflib
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SUITE = Path(__file__).with_name("cases.json")
MARKER = ".countdown-agent-evals"
HOOK_FIXTURE = "HarnessFixture/swift_harness.py"


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(root):
    """Include untracked additions and removals; never follow symlinks."""
    values = {}
    for base, directories, files in os.walk(root, followlinks=False):
        directories[:] = sorted(d for d in directories if d not in {".git", ".build", ".swiftpm"}
                                and not d.endswith(".app")
                                and (Path(base) / d).relative_to(root).as_posix() != "evals/artifacts")
        for name in list(directories):
            path = Path(base) / name
            if path.is_symlink():
                values[path.relative_to(root).as_posix()] = "symlink:" + os.readlink(path)
                directories.remove(name)
        for name in sorted(files):
            path = Path(base) / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                values[relative] = "symlink:" + os.readlink(path)
            else:
                values[relative] = digest(path)
    return values


def load_suite():
    suite = json.loads(SUITE.read_text())
    ids = [case["id"] for case in suite["cases"]]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate case ids")
    for case in suite["cases"]:
        if not case["rubric"] or len({r["id"] for r in case["rubric"]}) != len(case["rubric"]):
            raise ValueError("Invalid rubric: " + case["id"])
    return suite


def replace_once(path, before, after):
    value = path.read_text()
    if value.count(before) != 1:
        raise ValueError(f"Fixture no longer applies exactly once: {path.name}")
    path.write_text(value.replace(before, after, 1))


def inject(root, fixture):
    if fixture == "today-label":
        replace_once(root / "Sources/CountdownCore/Countdown.swift",
                     'count == 0 ? "Сегодня" : dayLabel(count)', 'dayLabel(count)')
    elif fixture == "readonly-hook":
        target = root / HOOK_FIXTURE
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / ".codex/hooks/swift_harness.py", target)
        replace_once(target, "    if not changed:\n", "    if not changed and not previous:\n")
    elif fixture == "alert-click":
        replace_once(root / "Sources/CountdownManager/TimerCompletionAlert.swift",
                     "panel.ignoresMouseEvents = false", "panel.ignoresMouseEvents = true")
    elif fixture == "load-failure":
        replace_once(root / "Sources/CountdownManager/Store.swift",
                     "            readFailed = true\n",
                     '            readFailed = false\n            data = CountdownData()\n'
                     '            stagePersistence(data, reason: "recover-load")\n')
    elif fixture == "readme-typo":
        replace_once(root / "README.md", "agent harness для сопровождения", "agent harnees для сопровождения")
    elif fixture is not None:
        raise ValueError("Unknown fixture: " + fixture)


def execute(command, cwd, timeout, stdout, stderr, stdin=None, env=None):
    """Keep traces on failure and terminate the whole process group on timeout."""
    started = time.monotonic()
    with stdout.open("wb") as out, stderr.open("wb") as err:
        child = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                 stdout=out, stderr=err, start_new_session=True)
        timed_out = False
        try:
            child.communicate(stdin.encode() if stdin is not None else b"", timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.communicate()
    return {"exit_code": child.returncode, "timed_out": timed_out,
            "seconds": round(time.monotonic() - started, 3)}


def parse_trace(path):
    events, malformed = [], []
    for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
            if not isinstance(event, dict):
                raise ValueError("Event is not an object")
            events.append(event)
        except (ValueError, json.JSONDecodeError):
            malformed.append(number)
    return events, malformed


def completed_commands(events):
    return [e["item"] for e in events if e.get("type") == "item.completed"
            and isinstance(e.get("item"), dict)
            and e["item"].get("type") == "command_execution"]


def shell_commands(command):
    """Recognize ordinary shell invocations; do not treat quoted mentions as execution."""
    try:
        words = shlex.split(command)
        if words and Path(words[0]).name in {"sh", "bash", "zsh"}:
            flag = next((i for i, word in enumerate(words[1:], 1)
                         if word in {"-c", "-lc", "-ic", "-lic"}), None)
            if flag is not None and flag + 1 < len(words):
                command = words[flag + 1]
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|\n")
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        lexer.commenters = ""
        groups, current = [], []
        for word in lexer:
            if word and set(word) <= set(";&|\n"):
                if current:
                    groups.append(current)
                current = []
            else:
                current.append(word)
        if current:
            groups.append(current)
        result = []
        for words in groups:
            while words and (words[0] == "env" or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0])):
                words = words[1:]
            if words and Path(words[0]).name in {"sh", "bash", "zsh"}:
                words = words[1:]
            if words:
                result.append(words)
        return result
    except ValueError:
        return []


def verification_invocations(command):
    checks = set()
    loop_targets = {}
    for words in shell_commands(command):
        if len(words) >= 4 and words[0] == "for" and words[2] == "in":
            loop_targets[words[1]] = set(words[3:]) & {"CoreChecks", "UIChecks"}
            continue
        if words[0] == "done":
            loop_targets.clear()
            continue
        if words[0] == "do":
            words = words[1:]
            if not words:
                continue
        program, arguments = Path(words[0]).name, words[1:]
        expanded_targets = set()
        for variable, targets in loop_targets.items():
            if "$" + variable in arguments or "${" + variable + "}" in arguments:
                expanded_targets.update(targets)
        if program == "verify.sh":
            mode = arguments[0] if arguments else "full"
            if mode in {"fast", "full"}:
                checks.update({"core-checks", "ui-checks"})
            if mode in {"ui", "full", "capture"}:
                checks.update({"real-ui", "app-build"})
        information_query = program in {"swift", "swiftc", "xcodebuild"} and any(
            arg in {"--version", "-version", "--help", "-help", "-h", "-list", "-showsdks",
                    "-showBuildSettings", "-showdestinations", "-print-target-info", "-print-supported-features"}
            for arg in arguments
        )
        if program == "run-xcui-tests.sh" or (program == "xcodebuild" and "test" in arguments and not information_query):
            checks.update({"xcui", "app-build"})
        if not information_query and ((program == "swift" and "build" in arguments) or program in {"swiftc", "xcodebuild"}):
            checks.add("app-build")
        if program == "swiftlint" and "lint" in arguments:
            checks.add("swiftlint")
        for target, name in (("CoreChecks", "core-checks"), ("UIChecks", "ui-checks")):
            if program == target or (program == "swift" and "run" in arguments
                                     and (target in arguments or target in expanded_targets)):
                checks.add(name)
        if re.fullmatch(r"python(?:3(?:\.\d+)?)?", program):
            if any(arg.endswith("Tests/test_swift_harness.py") for arg in arguments):
                checks.add("hook-tests")
            if "-m" in arguments and "unittest" in arguments and "Tests.test_swift_harness" in arguments:
                checks.add("hook-tests")
    return checks


def verified_operations(command):
    if command.get("exit_code") != 0:
        return set()
    invocations = verification_invocations(command.get("command", ""))
    output = command.get("aggregated_output", "")
    verified = set()
    if "swiftlint" in invocations:
        verified.add("swiftlint")  # Successful quiet SwiftLint may emit no text.
    if "core-checks" in invocations and re.search(r"(?m)^PASS unit:", output):
        verified.add("core-checks")
    if "ui-checks" in invocations and re.search(r"(?m)^PASS UI state:", output):
        verified.add("ui-checks")
    if "hook-tests" in invocations:
        summaries = re.findall(r"Ran ([1-9][0-9]*) tests? in [^\n]*\n\s*\n(OK|FAILED[^\n]*)", output)
        if summaries and summaries[-1][1] == "OK":
            verified.add("hook-tests")
    return verified


def check(name, passed, evidence):
    return {"id": name, "pass": bool(passed), "evidence": evidence}


def change_diff(before_bytes, workspace, changed):
    """Diff against the injected fixture, so seeds never masquerade as agent edits."""
    result = []
    for relative in changed:
        source = workspace / relative
        old = before_bytes.get(relative, b"")
        new = source.read_bytes() if source.is_file() and not source.is_symlink() else b""
        try:
            if b"\0" in old or b"\0" in new:
                raise UnicodeError("binary")
            old_text, new_text = old.decode(), new.decode()
        except UnicodeError:
            result.append(f"Binary or symlink change: {relative}\n")
            continue
        lines = list(difflib.unified_diff(old_text.splitlines(keepends=True),
                                         new_text.splitlines(keepends=True),
                                         fromfile="before/" + relative, tofile="after/" + relative))
        result.extend(line if line.endswith("\n") else line + "\n" for line in lines)
        if not lines:
            result.append(f"Symlink or file-kind change: {relative}\n")
    return "".join(result)


def grade(case, before, after, events, malformed, execution, final, oracle=None):
    changed = sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p))
    commands = completed_commands(events)
    completed = any(e.get("type") == "turn.completed" for e in events)
    failed = any(e.get("type") == "turn.failed" for e in events)
    infrastructure_ok = execution["exit_code"] == 0 and not execution["timed_out"] and completed and not failed
    checks = [
        check("complete-trace", not malformed and bool(events), {"malformed_lines": malformed}),
        check("final-answer", bool(final.strip()), "final.txt"),
        check("change-scope", all(any(fnmatch.fnmatchcase(p, pattern)
              for pattern in case["allowed_changes"]) for p in changed), changed),
    ]
    # Trace mentions are supporting process evidence, not proof of comprehension.
    successful = [c for c in commands if c.get("exit_code") == 0]
    for path in case["required_reads"]:
        reads = [c["id"] for c in successful if path in c.get("command", "")]
        checks.append(check("read:" + path, bool(reads), reads))
    for operation in case.get("required_checks", []):
        runs = [c["id"] for c in commands if operation in verified_operations(c)]
        checks.append(check("verification:" + operation, bool(runs), runs))
    for operation in case.get("forbidden_checks", []):
        runs = [c["id"] for c in commands if operation in verification_invocations(c.get("command", ""))]
        checks.append(check("no-verification:" + operation, not runs, runs))
    for path in case.get("forbidden_reads", []):
        reads = [c["id"] for c in successful if path in c.get("command", "")]
        checks.append(check("no-read:" + path, not reads, reads))
    if case["oracle"]:
        checks.append(check("independent-oracle", oracle is not None and oracle["exit_code"] == 0
                            and not oracle["timed_out"], oracle))
    if case["allowed_changes"]:
        checks.append(check("fix-present", bool(changed), changed))
    return {"status": "INFRA_ERROR" if not infrastructure_ok else
            ("FAIL" if not all(c["pass"] for c in checks) else "REVIEW_REQUIRED"),
            "checks": checks, "changed_paths": changed, "commands": len(commands),
            "usage": [e.get("usage") for e in events if e.get("type") == "turn.completed"]}


def oracle(case, workspace, output):
    if case["oracle"] == "readonly-hook":
        # Use the immutable original test file, so the subject cannot weaken its judge.
        command = ["/usr/bin/python3", "-B", str(ROOT / "Tests/test_swift_harness.py")]
        env = os.environ.copy()
        env["SWIFT_HARNESS_PATH"] = str(workspace / HOOK_FIXTURE)
        result = execute(command, workspace, 60, output / "oracle.stdout", output / "oracle.stderr", env=env)
        result["phase"] = "runtime"
        return result
    if case["oracle"] == "today-label":
        with tempfile.TemporaryDirectory(prefix="countdown-eval-oracle-", dir="/private/tmp") as directory:
            probe = Path(directory)
            (probe / "main.swift").write_text('''import Foundation
let cases = [(0, "Сегодня"), (1, "1 день"), (2, "2 дня"), (5, "5 дней"),
             (11, "11 дней"), (14, "14 дней"), (21, "21 день"), (112, "112 дней")]
for (value, expected) in cases {
    guard countdownLabel(value) == expected else {
        fputs("FAIL: \\(value): \\(countdownLabel(value)) != \\(expected)\\n", stderr)
        exit(1)
    }
}
print("PASS: independent today and pluralization checks")
''')
            result = execute(["swiftc", str(workspace / "Sources/CountdownCore/Countdown.swift"),
                              str(probe / "main.swift"), "-module-cache-path", str(probe / "module-cache"),
                              "-o", str(probe / "check")], workspace,
                             120, output / "oracle-build.stdout", output / "oracle-build.stderr")
            if result["exit_code"] != 0 or result["timed_out"]:
                result["phase"] = "build"
                return result
            result = execute([str(probe / "check")], workspace, 15,
                             output / "oracle.stdout", output / "oracle.stderr")
            result["phase"] = "runtime"
            return result
    return None


def prepare(workspace, case):
    subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", "--no-local", "--", str(ROOT), str(workspace)],
                   check=True, capture_output=True)
    subprocess.run(["git", "-C", str(workspace), "remote", "remove", "origin"], check=True)
    # Overlay current tracked and nonignored source; never copy graders, artifacts or git internals.
    files = subprocess.check_output(["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=ROOT)
    copied = set()
    for raw in files.split(b"\0"):
        if not raw:
            continue
        relative = raw.decode(errors="surrogateescape")
        if relative.startswith("evals/") or relative == "Tests/test_agent_evals.py":
            continue
        source, destination = ROOT / relative, workspace / relative
        if source.is_symlink():
            raise ValueError("Symlink not permitted in eval input: " + relative)
        if source.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            copied.add(relative)
        elif destination.is_file():
            destination.unlink()  # a tracked deletion in the current working tree
    # A later committed suite still must not leak hidden graders into the subject's checkout.
    shutil.rmtree(workspace / "evals", ignore_errors=True)
    (workspace / "Tests/test_agent_evals.py").unlink(missing_ok=True)
    inject(workspace, case["fixture"])
    return copied


def run_case(case, output, args):
    output.mkdir()
    with tempfile.TemporaryDirectory(prefix="countdown-agent-eval-", dir="/private/tmp") as temporary:
        workspace = Path(temporary) / "repo"
        prepare(workspace, case)
        before = snapshot(workspace)
        before_bytes = {path: (workspace / path).read_bytes() for path in before
                        if (workspace / path).is_file() and not (workspace / path).is_symlink()}
        write_json(output / "before.json", before)
        # The fixture must fail its independent oracle before any agent gets a chance to edit it.
        preflight = output / "preflight"
        preflight.mkdir()
        initial_oracle = oracle(case, workspace, preflight)
        if case["oracle"] and (initial_oracle["exit_code"] != 1 or initial_oracle["timed_out"]
                               or initial_oracle["phase"] != "runtime"):
            raise ValueError("Fixture did not reproduce the defect: " + case["id"])
        prompt = ("Рабочая папка — отдельная копия Countdown Manager для оценки. Соблюдай её AGENTS.md. "
                  "Не обращайся к данным установленного приложения. Не выполняй commit, push, "
                  "установку или публикацию. Работай самостоятельно в пределах задачи.\n\n" + case["prompt"])
        (output / "prompt.txt").write_text(prompt)
        command = [args.codex, "exec", "--ignore-user-config", "--ephemeral", "--json",
                   "--sandbox", "workspace-write", "-c", 'approval_policy="never"',
                   "-c", 'features.multi_agent=false', "-c", f'model_reasoning_effort="{args.effort}"',
                   "-C", str(workspace), "-o", str(output / "final.txt")]
        if args.model:
            command += ["--model", args.model]
        command += ["-"]
        write_json(output / "command.json", command)
        execution = execute(command, workspace, args.timeout, output / "trace.jsonl",
                            output / "stderr.txt", stdin=prompt)
        after = snapshot(workspace)
        write_json(output / "after.json", after)
        write_json(output / "execution.json", execution)
        events, malformed = parse_trace(output / "trace.jsonl")
        final_path = output / "final.txt"
        final = final_path.read_text() if final_path.exists() else ""
        if not final:
            final = "\n".join(e["item"].get("text", "") for e in events
                              if e.get("type") == "item.completed"
                              and e.get("item", {}).get("type") == "agent_message")
            final_path.write_text(final)
        result = oracle(case, workspace, output) if case["oracle"] else None
        report = grade(case, before, after, events, malformed, execution, final, result)
        write_json(output / "checks.json", report)
        (output / "diff.patch").write_text(change_diff(before_bytes, workspace, report["changed_paths"]))
        changes = output / "changed-files"
        for relative in report["changed_paths"]:
            source = workspace / relative
            if source.is_file() and not source.is_symlink():
                destination = changes / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
        write_json(output / "review.json", {"reviewer": None, "checks": [
            {"id": rule["id"], "requirement": rule["requirement"], "pass": None, "evidence": ""}
            for rule in case["rubric"]]})
    print(f"{output.name}: {report['status']} ({report['commands']} commands)", flush=True)


def summary(output):
    if not (output / MARKER).is_file():
        raise ValueError("Not a marked eval run")
    manifest = json.loads((output / "manifest.json").read_text())
    suite = json.loads((output / "suite.json").read_text())
    expected = {f"{case['id']}-{repetition}": case for case in suite["cases"]
                if case["id"] in manifest["case_ids"]
                for repetition in range(1, manifest["repeat"] + 1)}
    results = []
    for case_dir in sorted(p for p in output.iterdir() if p.is_dir()):
        checks_path = case_dir / "checks.json"
        if not checks_path.exists():
            continue
        checks = json.loads(checks_path.read_text())
        review = json.loads((case_dir / "review.json").read_text())
        verdict = checks["status"]
        case = expected.get(case_dir.name)
        if case is None:
            raise ValueError("Unexpected case artifact: " + case_dir.name)
        exact_rubric = [c["id"] for c in review["checks"]] == [c["id"] for c in case["rubric"]]
        accepted = exact_rubric and review.get("reviewer") and review["checks"] and all(
            isinstance(c.get("pass"), bool) and c.get("evidence", "").strip() for c in review["checks"])
        rubric_failures = ["rubric:" + c["id"] for c in review["checks"] if not c["pass"]] if accepted else []
        if verdict == "REVIEW_REQUIRED" and accepted:
            verdict = "FAIL" if rubric_failures else "PASS"
        results.append({"case": case_dir.name, "status": verdict,
                        "failed_checks": [c["id"] for c in checks["checks"] if not c["pass"]] + rubric_failures})
    if len(results) != manifest["expected_runs"]:
        overall = "INCOMPLETE"
    elif any(r["status"] == "INFRA_ERROR" for r in results):
        overall = "INFRA_ERROR"
    elif any(r["status"] == "FAIL" for r in results):
        overall = "FAIL"
    elif any(r["status"] == "REVIEW_REQUIRED" for r in results):
        overall = "REVIEW_REQUIRED"
    else:
        overall = "PASS"
    value = {"status": overall, "runs": results}
    write_json(output / "summary.json", value)
    print(json.dumps(value, ensure_ascii=False, indent=2))
    return 0 if overall == "PASS" else 1


def recheck(source, output):
    """Reinterpret frozen traces with a corrected judge; never run or alter the subject."""
    if not (source / MARKER).is_file():
        raise ValueError("Not a marked eval run")
    if source == output or source in output.parents:
        raise ValueError("Recheck output must be separate from the original run")
    suite = json.loads((source / "suite.json").read_text())
    if suite.get("version", 0) < 2:
        raise ValueError("Version-1 literal-command criteria cannot be silently replaced; use a new suite run")
    manifest = json.loads((source / "manifest.json").read_text())
    output.mkdir(parents=True, exist_ok=False)
    (output / MARKER).touch()
    shutil.copy2(source / "suite.json", output / "suite.json")
    write_json(output / "manifest.json", {
        **manifest, "created_utc": datetime.now(timezone.utc).isoformat(),
        "rechecked_from": str(source), "execution_reused": True,
        "original_runner_sha256": manifest["runner_sha256"], "runner_sha256": digest(Path(__file__)),
    })
    for case in suite["cases"]:
        if case["id"] not in manifest["case_ids"]:
            continue
        for repetition in range(1, manifest["repeat"] + 1):
            name = f"{case['id']}-{repetition}"
            original, destination = source / name, output / name
            if not original.exists():
                continue  # Summary keeps the missing result visibly INCOMPLETE.
            shutil.copytree(original, destination)
            previous = json.loads((original / "checks.json").read_text())
            shutil.copy2(original / "checks.json", destination / "checks.original.json")
            if previous["status"] == "INFRA_ERROR":
                continue
            oracle_result = next((c["evidence"] for c in previous["checks"]
                                  if c["id"] == "independent-oracle"), None)
            events, malformed = parse_trace(original / "trace.jsonl")
            result = grade(case, json.loads((original / "before.json").read_text()),
                           json.loads((original / "after.json").read_text()), events, malformed,
                           json.loads((original / "execution.json").read_text()),
                           (original / "final.txt").read_text(), oracle_result)
            result["rechecked_from"] = str(original)
            write_json(destination / "checks.json", result)
    return summary(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("list")
    run = sub.add_parser("run")
    run.add_argument("--case", action="append", default=[])
    run.add_argument("--repeat", type=int, default=1)
    run.add_argument("--timeout", type=int, default=600)
    run.add_argument("--model", help="Exact supported CLI model; omission uses CLI's own default")
    run.add_argument("--effort", choices=["low", "medium", "high", "xhigh"], default="high")
    run.add_argument("--codex", default="codex")
    run.add_argument("--output", type=Path, required=True, help="New artifact directory; never overwritten")
    summarize = sub.add_parser("summarize")
    summarize.add_argument("output", type=Path)
    inspect = sub.add_parser("recheck")
    inspect.add_argument("source", type=Path)
    inspect.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    suite = load_suite()
    if args.action == "list":
        for case in suite["cases"]:
            print(case["id"] + ": " + case["prompt"])
        return 0
    if args.action == "summarize":
        return summary(args.output.resolve())
    if args.action == "recheck":
        return recheck(args.source.resolve(), args.output.resolve())
    if args.repeat < 1 or args.timeout < 1:
        parser.error("repeat and timeout must be positive")
    cases = [c for c in suite["cases"] if not args.case or c["id"] in args.case]
    if set(args.case) - {c["id"] for c in cases}:
        parser.error("Unknown case")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / MARKER).touch()
    source = snapshot(ROOT)
    version = subprocess.check_output([args.codex, "--version"], text=True).strip()
    write_json(output / "manifest.json", {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "source_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_digest": hashlib.sha256(json.dumps(source, sort_keys=True).encode()).hexdigest(),
        "suite_sha256": digest(SUITE), "runner_sha256": digest(Path(__file__)),
        "codex_version": version, "model": args.model or "CLI-default (unresolved)",
        "reasoning_effort": args.effort, "user_config": "ignored", "subject_sandbox": "workspace-write",
        "native_hook_trust": "not bypassed; hook registration is not evaluated",
        "expected_runs": len(cases) * args.repeat, "repeat": args.repeat,
        "case_ids": [case["id"] for case in cases],
    })
    shutil.copy2(SUITE, output / "suite.json")
    for repetition in range(1, args.repeat + 1):
        for case in cases:
            case_output = output / f"{case['id']}-{repetition}"
            try:
                run_case(case, case_output, args)
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                case_output.mkdir(exist_ok=True)
                write_json(case_output / "checks.json", {
                    "status": "INFRA_ERROR", "checks": [], "error": str(error)})
                write_json(case_output / "review.json", {"reviewer": None, "checks": []})
                print(f"{case_output.name}: INFRA_ERROR: {error}", flush=True)
    return summary(output)


if __name__ == "__main__":
    raise SystemExit(main())
