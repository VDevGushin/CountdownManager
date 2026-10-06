"""Opt-in native Codex hook delivery check against an isolated project copy."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import tempfile
import threading
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True, help='New artifact directory; never overwritten')
parser.add_argument('--model', required=True, help='Exact supported Codex model')
args = parser.parse_args()
CLI_VERSION = subprocess.check_output(['codex', '--version'], text=True).strip()
if CLI_VERSION != 'codex-cli 0.157.1':
    parser.error('Native protocol/trust handling is verified only for codex-cli 0.157.1')
ROOT = Path(__file__).resolve().parents[1]
OUT = args.output.resolve()
OUT.mkdir(parents=True, exist_ok=False)
CONFIG = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))) / 'config.toml'
CONFIG_BEFORE = hashlib.sha256(CONFIG.read_bytes()).hexdigest()
SPEC = importlib.util.spec_from_file_location('eval_setup', ROOT / 'evals/run.py')
setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(setup)


def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def overrides(key, value):
    return ['-c', key + '=' + json.dumps(value)]


class Server:
    def __init__(self, cwd, arguments, name):
        self.events = []
        self.inbox = queue.Queue()
        self.next_id = 0
        self.log = (OUT / (name + '.jsonl')).open('w')
        self.stderr = (OUT / (name + '.stderr')).open('w')
        try:
            self.process = subprocess.Popen(['codex', 'app-server', '--stdio'] + arguments,
                cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.stderr,
                text=True, bufsize=1)
        except Exception:
            self.log.close()
            self.stderr.close()
            raise
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()
        try:
            self.request('initialize', {'clientInfo': {'name': 'countdown_native_hooks_check', 'version': '1'},
                                        'capabilities': {'experimentalApi': True}})
            self.send({'method': 'initialized'})
        except Exception:
            self.close()
            raise

    def read(self):
        for line in self.process.stdout:
            self.log.write(line)
            self.log.flush()
            try:
                event = json.loads(line)
            except ValueError:
                continue
            self.events.append(event)
            self.inbox.put(event)

    def send(self, value):
        self.process.stdin.write(json.dumps(value) + '\n')
        self.process.stdin.flush()

    def request(self, method, params, timeout=120):
        self.next_id += 1
        identity = self.next_id
        self.send({'id': identity, 'method': method, 'params': params})
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            event = self.inbox.get(timeout=max(0.1, deadline - time.monotonic()))
            if event.get('id') == identity:
                if 'error' in event:
                    raise RuntimeError(f'{method}: {event["error"]}')
                return event['result']
            if 'id' in event and 'method' in event:
                raise RuntimeError('Unexpected client approval request: ' + event['method'])
        raise TimeoutError(method)

    def phase(self, thread_id, name, prompt, required_block=None, timeout=600):
        start = len(self.events)
        self.request('turn/start', {'threadId': thread_id, 'input': [{'type': 'text', 'text': prompt}], 'effort': 'high'})
        deadline = time.monotonic() + timeout
        seen_block = required_block is None
        while time.monotonic() < deadline:
            try:
                event = self.inbox.get(timeout=1)
            except queue.Empty:
                if self.process.poll() is not None:
                    raise RuntimeError('App-server exited')
                continue
            if 'id' in event and 'method' in event:
                raise RuntimeError('Unexpected approval request: ' + event['method'])
            if event.get('method') == 'hook/completed':
                run = event['params']['run']
                print(name, run['eventName'], run['status'], flush=True)
                if run['eventName'] == required_block and run['status'] == 'blocked':
                    seen_block = True
            if event.get('method') == 'turn/completed':
                status = event['params'].get('turn', {}).get('status')
                if status != 'completed':
                    raise RuntimeError(name + ': ' + str(event['params']))
                recent = self.events[start:]
                stops = [x['params']['run'] for x in recent if x.get('method') == 'hook/completed'
                         and x['params']['run']['eventName'] == 'stop']
                if stops and stops[-1]['status'] == 'completed' and seen_block:
                    save(name + '.events.json', recent)
                    return recent
        save(name + '.events.json', self.events[start:])
        raise TimeoutError(name)

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(timeout=10)
        self.reader.join(timeout=3)
        self.log.close()
        self.stderr.close()


def state(fixture, thread_id):
    key = hashlib.sha256(thread_id.encode()).hexdigest()
    p = fixture / '.git/codex-hook-state' / (key + '.json')
    return json.loads(p.read_text())


with tempfile.TemporaryDirectory(prefix='countdown-native-hooks-', dir='/private/tmp') as temporary:
    fixture = Path(temporary) / 'repo'
    setup.prepare(fixture, {'fixture': None})
    hook = fixture / '.codex/hooks/swift_harness.py'
    assert hook.read_bytes() == (ROOT / '.codex/hooks/swift_harness.py').read_bytes()
    assert (fixture / '.codex/hooks.json').read_bytes() == (ROOT / '.codex/hooks.json').read_bytes()
    probe = fixture / 'Sources/CountdownCore/NativeHookProbe.swift'
    probe.write_text('let nativeHookProbe = 0\n')
    arguments = ['-c', 'projects={' + json.dumps(str(fixture)) + '={trust_level="trusted"}}']
    for feature in ['apps', 'plugins', 'memories', 'multi_agent']:
        arguments += overrides('features.' + feature, False)
    arguments += overrides('mcp_servers.node_repl.enabled', False)
    discovery = Server(fixture, arguments, 'discovery')
    try:
        metadata = discovery.request('hooks/list', {'cwds': [str(fixture)]})
        save('hooks.before-trust.json', metadata)
    finally:
        discovery.close()
    registered = {}
    current = None
    for line in CONFIG.read_text().splitlines():
        match = re.fullmatch(r'\[hooks\.state\."(.*)"\]', line)
        if match:
            current = match.group(1)
        elif line.startswith('['):
            current = None
        elif current and line.startswith('trusted_hash = '):
            registered[current] = json.loads(line.split('=', 1)[1].strip())
    hooks = metadata['data'][0]['hooks']
    local = [h for h in hooks if h['sourcePath'] == str(fixture / '.codex/hooks.json')]
    assert len(local) == 3, metadata
    assert not [h for h in hooks if h not in local and h['enabled'] and not h['isManaged']], metadata
    trusted_entries = []
    for h in local:
        suffix = h['key'].split('.codex/hooks.json:', 1)[1]
        original_key = str(ROOT / '.codex/hooks.json') + ':' + suffix
        assert registered[original_key] == h['currentHash'], (original_key, h)
        trusted_entries.append(json.dumps(h['key']) + '={trusted_hash=' + json.dumps(registered[original_key]) + ',enabled=true}')
    arguments += ['-c', 'hooks.state={' + ','.join(trusted_entries) + '}']
    server = Server(fixture, arguments, 'native-runtime')
    try:
        metadata = server.request('hooks/list', {'cwds': [str(fixture)]})
        save('hooks.trusted.json', metadata)
        local = [h for h in metadata['data'][0]['hooks'] if h['sourcePath'] == str(fixture / '.codex/hooks.json')]
        assert len(local) == 3 and all(h['enabled'] and h['trustStatus'] == 'trusted' for h in local), metadata
        result = server.request('thread/start', {'cwd': str(fixture), 'model': args.model,
            'approvalPolicy': 'never', 'sandbox': 'workspace-write', 'ephemeral': True})
        thread_id = result['thread']['id']
        save('manifest.json', {'cli': CLI_VERSION, 'fixture': str(fixture), 'thread_id': thread_id,
             'hook_source_sha256': hashlib.sha256(hook.read_bytes()).hexdigest(),
             'hooks_config_sha256': hashlib.sha256((fixture / '.codex/hooks.json').read_bytes()).hexdigest(),
             'verify_sha256': hashlib.sha256((fixture / 'verify.sh').read_bytes()).hexdigest(),
             'lint_config_sha256': hashlib.sha256((fixture / '.swiftlint.yml').read_bytes()).hexdigest(),
             'trust': 'ephemeral SessionFlags with exact already-reviewed hashes; no bypass',
             'model': args.model, 'script_and_config_byte_identical': True,
             'production_config_sha256_before': CONFIG_BEFORE})
        read_events = server.phase(thread_id, 'read-only',
            'This is an isolated native hook integration check. Read only the first heading of README.md with a tool and report it. Do not modify any files, do not manually run verification commands. No commits, push, installs or production data access.')
        read_state = state(fixture, thread_id)
        save('read-only.state.json', read_state)
        assert read_state['swift_touched'] is False
        probe.write_text('let nativeHookProbe :Int=0\n')
        server.phase(thread_id, 'post-lint',
            'In this isolated copy, make only the formatting of Sources/CountdownCore/NativeHookProbe.swift correct. Do not manually run lint or tests. Correct any issues reported by automatic hooks and then finish. Do not modify hook scripts or verification configuration. No production data, commit, push or installation.',
            required_block='postToolUse')
        save('post-lint.state.json', state(fixture, thread_id))
        core = fixture / 'Sources/CountdownCore/Countdown.swift'
        value = core.read_text()
        old = 'count == 0 ? "\u0421\u0435\u0433\u043e\u0434\u043d\u044f" : dayLabel(count)'
        assert value.count(old) == 1
        core.write_text(value.replace(old, 'dayLabel(count)'))
        server.phase(thread_id, 'stop-regression',
            'In this isolated copy, add exactly the comment // native stop check to Sources/CountdownCore/NativeHookProbe.swift and finish. Do not manually run tests or inspect/change other files before actual automatic-hook feedback. If an automatic hook reports a regression, fix only its cause without changing tests or hook/verification configuration, then finish. No production data, commit, push or installation.',
            required_block='stop')
        final_state = state(fixture, thread_id)
        save('stop-regression.state.json', final_state)
        assert final_state['last_gate_pass']
        assert old in core.read_text()
        assert CONFIG_BEFORE == hashlib.sha256(CONFIG.read_bytes()).hexdigest(), 'Production config changed during test'
        save('result.json', {'status': 'PASS', 'production_config_unchanged': True,
                             'phases': ['sessionStart', 'readOnly', 'postToolUseBlockAndRepair', 'stopBlockAndRepair']})
        print('PASS: native SessionStart, read-only, PostToolUse block/repair, Stop block/repair', flush=True)
    finally:
        server.close()
