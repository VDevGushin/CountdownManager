#!/usr/bin/env python3
"""Prepare two genuinely built Sparkle fixtures with a disposable file-based key."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import update_tools


def build_input_hashes():
    paths = [update_tools.ROOT / name for name in
             ("Package.swift", "Package.resolved", "build.sh", "verify.sh")]
    paths += [path for base in ("Sources", "Resources", "scripts")
              for path in (update_tools.ROOT / base).rglob("*") if path.is_file()
              and "__pycache__" not in path.parts]
    return {str(path.relative_to(update_tools.ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(paths)}


def toolchain_snapshot():
    commands = {
        "swift_version": ["/usr/bin/swift", "--version"],
        "macos_version": ["/usr/bin/sw_vers", "-productVersion"],
        "macos_build": ["/usr/bin/sw_vers", "-buildVersion"],
        "architecture": ["/usr/bin/uname", "-m"],
        "developer_directory": ["/usr/bin/xcode-select", "-p"],
    }
    return {name: update_tools.run(command, capture=True).stdout.strip()
            for name, command in commands.items()}


def require_unchanged_inputs(expected, actual):
    changed = sorted(name for name in expected.keys() | actual.keys()
                     if expected.get(name) != actual.get(name))
    if changed:
        update_tools.fail("Build inputs changed during fixture preparation: " + ", ".join(changed))


def prepare(args):
    root = Path(args.output).expanduser().resolve() if args.output else Path(
        tempfile.mkdtemp(prefix="countdown-update-test.", dir="/private/tmp"))
    if root == update_tools.ROOT or update_tools.ROOT in root.parents:
        update_tools.fail("Test fixtures must be outside the repository")
    if root.exists() and any(root.iterdir()):
        update_tools.fail("Test fixture output must be an empty directory")
    root.mkdir(parents=True, exist_ok=True)
    hashes_before = build_input_hashes()
    toolchain_before = toolchain_snapshot()
    inputs_before = {"captured_before_build_at": datetime.now(timezone.utc).isoformat(),
                     "sha256": hashes_before, "toolchain": toolchain_before}
    (root / "build-inputs-before.json").write_text(json.dumps(inputs_before, indent=2) + "\n")
    home = root / "test-home"
    home.mkdir()
    (home / update_tools.TEST_MARKER).touch()
    private = root / "test-only-private-key"
    descriptor = os.open(private, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, "w") as target:
        target.write(base64.b64encode(os.urandom(32)).decode() + "\n")
    public = update_tools.public_key(update_tools.key_public(private))
    (root / "test-only-public-key.txt").write_text(public + "\n")
    feed = f"http://127.0.0.1:{args.port}/appcast.xml"
    apps = []
    environment = os.environ.copy()
    environment.update(COUNTDOWN_UPDATE_MODE="test", COUNTDOWN_UPDATE_FEED_URL=feed,
                       COUNTDOWN_UPDATE_PUBLIC_KEY=public, COUNTDOWN_MANAGER_TEST_HOME=str(home),
                       BUILD_DIR=str(Path(args.build_dir).resolve()))
    for label, version, build in (("older", "1.6.90", args.first_build),
                                  ("newer", "1.6.91", args.first_build + 1)):
        require_unchanged_inputs(hashes_before, build_input_hashes())
        require_unchanged_inputs(toolchain_before, toolchain_snapshot())
        app = root / label / "Countdown Manager.app"
        environment.update(APP_OUTPUT_PATH=str(app), COUNTDOWN_VERSION=version,
                           COUNTDOWN_BUILD_NUMBER=str(build))
        update_tools.run([update_tools.ROOT / "build.sh"], env=environment)
        require_unchanged_inputs(hashes_before, build_input_hashes())
        require_unchanged_inputs(toolchain_before, toolchain_snapshot())
        apps.append(app)
    output = root / "feed"
    release_args = argparse.Namespace(app=str(apps[1]), private_key=str(private),
                                     build_dir=args.build_dir, output=str(output), test=True,
                                     download_url_prefix=f"http://127.0.0.1:{args.port}/")
    update_tools.release(release_args)
    launch = root / "launch-older.sh"
    # shell-safe argument quoting; no signing key appears in the launcher.
    import shlex
    launch.write_text("#!/bin/bash\nset -euo pipefail\nexec /usr/bin/open -n "
                      + shlex.quote(str(apps[0])) + " --args --update-test\n")
    launch.chmod(0o700)
    serve = root / "serve-feed.sh"
    serve.write_text("#!/bin/bash\nset -euo pipefail\nexec python3 -m http.server "
                     + str(args.port) + " --bind 127.0.0.1 --directory "
                     + shlex.quote(str(output)) + "\n")
    serve.chmod(0o700)
    require_unchanged_inputs(hashes_before, build_input_hashes())
    require_unchanged_inputs(toolchain_before, toolchain_snapshot())
    manifest = {"older_app": str(apps[0]), "newer_app": str(apps[1]),
                "older_build": args.first_build, "newer_build": args.first_build + 1,
                "bundle_identifier": update_tools.TEST_ID, "isolated_home": str(home),
                "feed_url": feed, "feed_directory": str(output),
                "launch_script": str(launch), "serve_script": str(serve),
                "source_sha256": hashes_before, "build_inputs_before": inputs_before,
                "build_inputs_unchanged_after_build": True, "provenance_schema": 2,
                "actual_update_verified": False,
                "note": "Disposable test-only signing key; never use for releases. Fixtures do not prove replacement/relaunch."}
    (root / "test-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Prepared isolated update fixtures: " + str(root))
    print("Start feed server: " + str(serve))
    print("Launch older app: " + str(launch))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output")
    parser.add_argument("--build-dir", default=str(update_tools.ROOT / ".build"))
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--first-build", type=int, default=20001)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535 or args.first_build <= 0:
        parser.error("port must be 1024...65535 and first build must be positive")
    try:
        prepare(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print("Test preparation failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
