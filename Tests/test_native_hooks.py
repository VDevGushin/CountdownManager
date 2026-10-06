"""Local protocol regression checks; no Codex process, model or hook execution."""

import ast
import contextlib
import io
from pathlib import Path
import queue
import threading
import time
import unittest
from unittest.mock import Mock, patch


def server_class():
    # Compile the transport class alone so importing the opt-in CLI cannot start a run.
    path = Path(__file__).resolve().parents[1] / 'evals/native_hooks.py'
    tree = ast.parse(path.read_text())
    node = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'Server')
    namespace = {'queue': queue, 'threading': threading, 'time': time, 'json': __import__('json'),
                 'subprocess': __import__('subprocess'), 'save': Mock()}
    exec(compile(ast.Module(body=[node], type_ignores=[]), str(path), 'exec'), namespace)
    return namespace['Server'], namespace


class NativeHookChecks(unittest.TestCase):
    def test_failed_interrupted_or_invalid_turn_cannot_pass_a_completed_stop(self):
        cls, namespace = server_class()
        stop = {'method': 'hook/completed', 'params': {'run': {'eventName': 'stop', 'status': 'completed'}}}
        for status in ('failed', 'interrupted', None):
            server = cls.__new__(cls)
            server.events = []
            server.inbox = queue.Queue()
            turn = {'method': 'turn/completed', 'params': {'turn': {'status': status}}}
            server.request = lambda *a, **k: server.events.extend([stop, turn])
            server.inbox.put(stop)
            server.inbox.put(turn)
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(RuntimeError):
                server.phase('thread', 'case', 'prompt')
        namespace['save'].assert_not_called()

    def test_completed_stop_and_completed_turn_pass(self):
        cls, namespace = server_class()
        server = cls.__new__(cls)
        server.events = []
        server.inbox = queue.Queue()
        events = [{'method': 'hook/completed', 'params': {'run': {'eventName': 'stop', 'status': 'completed'}}},
                  {'method': 'turn/completed', 'params': {'turn': {'status': 'completed'}}}]
        server.request = lambda *a, **k: server.events.extend(events)
        for event in events:
            server.inbox.put(event)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(server.phase('thread', 'case', 'prompt'), events)
        namespace['save'].assert_called_once_with('case.events.json', events)

    def test_initialize_failure_closes_the_started_process(self):
        import tempfile
        cls, namespace = server_class()
        with tempfile.TemporaryDirectory() as directory:
            namespace['OUT'] = Path(directory)
            process = Mock()
            process.stdout = []
            process.poll.return_value = None
            with patch.object(namespace['subprocess'], 'Popen', return_value=process), \
                 patch.object(cls, 'request', side_effect=RuntimeError('initialize failed')):
                with self.assertRaises(RuntimeError):
                    cls(Path(directory), [], 'test')
            process.stdin.close.assert_called_once()
            process.wait.assert_called_once()


if __name__ == '__main__':
    unittest.main()
