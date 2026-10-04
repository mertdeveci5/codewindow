"""Exercise the packaged reporter with live, quit, crashed and multiple app instances."""
from pathlib import Path
from contextlib import ExitStack
import json
import os
import subprocess
import sys
import tempfile
import time

from app_presence_fixture import running_app

reporter, host = map(Path, sys.argv[1:3])


def payload(event="UserPromptSubmit", prompt="test"):
    return json.dumps({"session_id": "lifecycle", "hook_event_name": event,
                      "cwd": "/tmp/test", "prompt": prompt,
                      "tool_name": "Bash", "tool_input": {"command": "echo test"}}).encode()


def command(agent="claude", inbox=False):
    return [str(reporter), "--agent", agent, "--pid", str(os.getpid())] + (["--inbox"] if inbox else [])


def run(state, agent="claude", inbox=False, data=None):
    result = subprocess.run(command(agent, inbox), input=payload() if data is None else data,
                            capture_output=True, timeout=3,
                            env=dict(os.environ, CODEWINDOW_STATE_DIR=str(state)))
    assert result.returncode == 0, (result.returncode, result.stderr)
    assert not result.stdout and not result.stderr, (result.stdout, result.stderr)


def snapshot(state):
    return {str(p.relative_to(state)): p.read_bytes() for p in state.rglob("*") if p.is_file()}


def quit_app(process, crash=False):
    if crash:
        process.kill()
    else:
        process.stdin.close()
    process.wait(timeout=3)


def wait_for_item(state):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        items = list((state / "Inbox/Items").glob("*.json"))
        if items:
            return items[0]
        time.sleep(0.02)
    raise AssertionError("Reporter did not enter an inbox wait")


with tempfile.TemporaryDirectory(prefix="codewindow-reporter-lifecycle-") as temporary:
    root = Path(temporary)
    state = root / "missing"
    for agent in ["claude", "codex", "pi"]:
        run(state, agent)
        run(state, agent, True, payload("PermissionRequest"))
        run(state, agent, data=b"not JSON")
    assert not state.exists(), "Closed-app hook created state"
    print("PASS closed-app hooks do not create state, parse payloads, or intercept permissions")

    state.mkdir()
    (state / "Inbox").mkdir()
    (state / "Inbox/.enabled").touch()
    before = snapshot(state)
    for agent in ["claude", "codex", "pi"]:
        run(state, agent)
        run(state, agent, True, payload("Stop"))
        run(state, agent, True, payload("PermissionRequest"))
    assert snapshot(state) == before, "Stale inbox preference activated a closed app"
    print("PASS persisted inbox preference alone cannot enable reporting or waits")

    with running_app(host, state):
        for agent in ["claude", "codex", "pi"]:
            run(state, agent)
        assert len(list(state.glob("*.json"))) == 3, "Live app missed agent reports"
    before = snapshot(state)
    run(state, data=payload(prompt="must not be recorded"))
    assert snapshot(state) == before
    print("PASS live app records all agents; normal quit stops writes")

    with running_app(host, state) as app:
        quit_app(app, crash=True)
        assert list((state / ".apps").glob("*.json")), "Crash fixture did not leave a stale marker"
        before = snapshot(state)
        run(state, data=payload(prompt="must not be recorded after crash"))
        assert snapshot(state) == before, "Crash marker kept reporter alive"
    with running_app(host, state):
        assert len(list((state / ".apps").glob("*.json"))) == 1, "Relaunch kept stale markers"
        run(state, data=payload(prompt="reopened"))
        assert any(json.loads(p.read_text()).get("taskPreview") == "reopened" for p in state.glob("*.json"))
    print("PASS crash stops writes; relaunch cleans markers and resumes without reinstalling hooks")

    for agent, event in [("claude", "PermissionRequest"), ("codex", "PermissionRequest"), ("claude", "Stop")]:
        for crash in [False, True]:
            with ExitStack() as stack:
                first = stack.enter_context(running_app(host, state))
                last = stack.enter_context(running_app(host, state))
                hook = subprocess.Popen(command(agent, True), stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        env=dict(os.environ, CODEWINDOW_STATE_DIR=str(state)))
                try:
                    hook.stdin.write(payload(event))
                    hook.stdin.close()
                    hook.stdin = None
                    item = wait_for_item(state)
                    quit_app(first, crash=crash)
                    time.sleep(0.4)
                    assert hook.poll() is None, "Quitting one instance released another app's wait"
                    started = time.monotonic()
                    quit_app(last, crash=crash)
                    stdout, stderr = hook.communicate(timeout=2)
                    assert time.monotonic() - started < 2
                    assert hook.returncode == 0 and not stdout and not stderr, (hook.returncode, stdout, stderr)
                    assert not item.exists(), "Released wait left an actionable inbox item"
                finally:
                    if hook.poll() is None:
                        hook.kill()
                        hook.communicate(timeout=3)
            print(f"PASS {agent} {event}: {'crash' if crash else 'quit'}, multi-instance wait released")
    assert (state / "Inbox/.enabled").exists(), "Quitting changed the inbox preference"
print("PASS reporter app lifecycle")
