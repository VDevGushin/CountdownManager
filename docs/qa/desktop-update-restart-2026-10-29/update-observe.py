"""Observe one already-running isolated update host; never click, launch, reopen or terminate it."""
from pathlib import Path
import argparse, datetime, hashlib, json, plistlib, re, subprocess, time

DEFAULT_ROOT = '/private/tmp/countdown-desktop-update-fix-20261029'

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def defaults_export(domain):
    result = subprocess.run(['/usr/bin/defaults', 'export', domain, '-'], capture_output=True)
    return plistlib.loads(result.stdout) if result.returncode == 0 else {}

def hosts(executable):
    aliases = [executable, executable.removeprefix('/private')] if executable.startswith('/private/tmp/') else [executable]
    result = []
    for line in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and any(parts[1] == name or parts[1].startswith(name + ' ') for name in aliases):
            result.append(int(parts[0]))
    return sorted(result)

def verify_data(snapshot):
    data_path = Path(snapshot['dataPath']); data = json.loads(data_path.read_text())
    assert digest(data_path) == snapshot['jsonSHA256'], 'Event JSON bytes changed'
    assert [item['id'] for item in data['items']] == snapshot['eventIDs'], 'Event identities changed'
    assert data['primaryID'] == snapshot['primaryID'], 'Primary changed'
    for record in snapshot['attachments']:
        assert digest(Path(record['copy'])) == record['sha256'], 'Owned copy bytes changed'
        assert digest(Path(record['original'])) == record['sha256'], 'Original bytes changed'
        assert digest(Path(record['marker'])) == record['markerSHA256'], 'Ownership marker changed'
    preferences = defaults_export(snapshot['defaultsDomain'])
    assert all(preferences.get(key) == value for key, value in snapshot['selectedPreferences'].items()), 'Selected preferences changed'
    return dict(jsonBytesPreserved=True, eventIdentitiesPreserved=True, primaryPreserved=True,
                ownedCopiesPreserved=True, ownershipMarkersPreserved=True, originalsPreserved=True,
                selectedPreferencesPreserved=True, selectedPreferenceKeys=list(snapshot['selectedPreferences']))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default=DEFAULT_ROOT); parser.add_argument('--old-pid', type=int, required=True)
    parser.add_argument('--timeout', type=float, default=120)
    args = parser.parse_args(); assert 0 < args.timeout <= 120
    root = Path(args.root).resolve(); assert str(root).startswith('/private/tmp/countdown-desktop-update-fix-')
    manifest = json.loads((root / 'test-manifest.json').read_text())
    snapshot = json.loads((root / 'seed-snapshot.json').read_text())
    home = Path(manifest['isolated_home']).resolve()
    assert home.parent == root and (home / '.countdown-update-test-environment').is_file()
    assert snapshot['isolatedHome'] == str(home) and manifest['bundle_identifier'] == 'local.countdownmanager.update-test'
    app = Path(manifest['older_app']).resolve(); assert root in app.parents
    executable = str(app / 'Contents/MacOS/CountdownManager')
    initial = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert initial['CFBundleVersion'] == str(manifest['older_build']), 'Host is not the older fixture'
    assert hosts(executable) == [args.old_pid], 'Expected exactly the specified old host PID'
    verify_data(snapshot)
    log = home / 'Application Support/CountdownManager/Logs/countdown.log'
    before_lines = log.read_text().splitlines() if log.exists() else []
    start = time.monotonic(); events = []; previous = None; stable = 0; observed_pid = None
    ready = dict(status='READY', oldPID=args.old_pid, expectedNewBuild=str(manifest['newer_build']),
                 executablePath=executable, startedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                 observationOnly=True, initialLogLines=len(before_lines), productionDataUsed=False)
    (root / 'observer-ready.json').write_text(json.dumps(ready, indent=2) + '\n')
    print(json.dumps(ready), flush=True)
    result = dict(ready, automaticRelaunchObserved=False, events=events)
    try:
        while time.monotonic() - start < args.timeout:
            pids = hosts(executable)
            try:
                info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
                build = info.get('CFBundleVersion'); version = info.get('CFBundleShortVersionString')
            except (OSError, ValueError): build = version = None
            text = log.read_text() if log.exists() else ''
            lines = text.splitlines(); newer_lines = lines[len(before_lines):]
            launch_indices = [index for index, line in enumerate(newer_lines)
                              if 'app.launch version=' in line and f' build={manifest["newer_build"]} ' in line]
            loaded_after_launch = bool(launch_indices and any('data.load success ' in line for line in newer_lines[launch_indices[-1] + 1:]))
            state = (tuple(pids), build, version, bool(launch_indices), loaded_after_launch)
            if state != previous:
                events.append(dict(elapsedSeconds=round(time.monotonic() - start, 3), pids=pids, build=build,
                                   version=version, newLaunchLogged=bool(launch_indices), dataLoadedAfterNewLaunch=loaded_after_launch))
                previous = state
            candidate = len(pids) == 1 and args.old_pid not in pids and build == str(manifest['newer_build']) and loaded_after_launch
            if candidate:
                stable = stable + 1 if observed_pid == pids[0] else 1; observed_pid = pids[0]
            else: stable = 0; observed_pid = None
            if stable >= 3:
                assert any('updates.install starting' in line for line in newer_lines), 'Installer start was not observed after READY'
                assert any('app.terminate' in line for line in newer_lines), 'Old host termination was not logged after READY'
                preserved = verify_data(snapshot)
                result.update(status='PASS', automaticRelaunchObserved=True, afterPID=observed_pid,
                              afterBuild=build, afterVersion=version, oldPIDExited=True, exactlyOneNewHost=True,
                              newLaunchLogged=True, dataLoadedAfterNewLaunch=True,
                              installerStartingLogged=any('updates.install starting' in line for line in newer_lines),
                              oldTerminationLogged=any('app.terminate' in line for line in newer_lines),
                              noUIActionsPerformedByObserver=True, noLaunchOrReopenPerformedByObserver=True,
                              manualReopenBeforeObservation=False,
                              manualReopenAssurance='Parent protocol forbids manual reopening after final click; observer performs read-only polling.',
                              elapsedSeconds=round(time.monotonic() - start, 3), preservation=preserved)
                break
            time.sleep(0.2)
        else:
            result.update(status='FAIL', reason='Timed out without one new PID, updated installed build and a new launch/data-load log')
    except Exception as error:
        result.update(status='FAIL', reason=str(error), errorType=type(error).__name__)
    (root / 'genuine-update-observation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
    raise SystemExit(0 if result.get('status') == 'PASS' else 1)

if __name__ == '__main__': main()
