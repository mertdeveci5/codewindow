#!/usr/bin/env python3
"""Verify installer trust against a real Codex CLI, using disposable profiles only."""

import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import tempfile
import time


class Codex:
    def __init__(self, executable, home):
        self.home = home
        self.process = subprocess.Popen(
            [executable, "app-server", "--stdio"],
            cwd=home,
            env=dict(os.environ, CODEX_HOME=str(home)),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = b""
        self.sequence = 0

    def __enter__(self):
        self.request("initialize", {
            "clientInfo": {"name": "codewindow_trust_test", "version": "1"},
            "capabilities": {"experimentalApi": True},
        })
        self.process.stdin.write(b'{"method":"initialized"}\n')
        self.process.stdin.flush()
        return self

    def __exit__(self, *_):
        self.process.kill()
        self.process.wait(timeout=5)
        self.process.stdin.close()
        self.process.stdout.close()
        self.selector.close()

    def request(self, method, params):
        self.sequence += 1
        self.process.stdin.write(json.dumps({
            "id": self.sequence, "method": method, "params": params,
        }).encode() + b"\n")
        self.process.stdin.flush()
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if b"\n" not in self.buffer:
                assert self.selector.select(max(0, deadline - time.monotonic())), method + " timed out"
                chunk = os.read(self.process.stdout.fileno(), 65536)
                assert chunk, method + " connection closed"
                self.buffer += chunk
                continue
            line, self.buffer = self.buffer.split(b"\n", 1)
            response = json.loads(line)
            if response.get("id") == self.sequence:
                assert "error" not in response, (method, response.get("error"))
                return response["result"]
        raise AssertionError(method + " timed out")

    def hooks(self):
        return self.request("hooks/list", {"cwds": [str(self.home)]})["data"][0]["hooks"]

    def write(self, edits):
        result = self.request("config/batchWrite", {"edits": edits, "reloadUserConfig": True})
        assert result["status"] == "ok"


def check(helper, codex):
    with tempfile.TemporaryDirectory(prefix="codewindow-hook-trust.") as temporary:
        # Quotes and spaces exercise the reporter command and escaped trust keys.
        home = Path(temporary) / "user's home"
        profiles = [home / ".codex", home / ".codex-second"]
        for profile in profiles:
            profile.mkdir(parents=True)
            (profile / "config.toml").write_text('model = "keep-me"\n')
            (profile / "hooks.json").write_text(json.dumps({"hooks": {
                "SessionStart": [{"hooks": [{"type": "command", "command": "/usr/bin/true"}]}],
                "Stop": [{"hooks": [{"type": "command", "command": "/usr/bin/false"}]}],
            }}))

        preserved = {}
        for profile in profiles:
            with Codex(codex, profile) as client:
                user_hook = next(h for h in client.hooks() if h["command"] == "/usr/bin/true")
                state = {user_hook["key"]: {"trusted_hash": user_hook["currentHash"], "enabled": False}}
                client.write([{"keyPath": "hooks.state", "value": state, "mergeStrategy": "upsert"}])
                preserved[profile] = user_hook

        def install(command, succeeds=True):
            result = subprocess.run(
                [str(helper), command, "--home", str(home)],
                env=dict(os.environ, CODEWINDOW_DISABLE_ANALYTICS="1"),
                capture_output=True, text=True, timeout=45,
            )
            assert (result.returncode == 0) == succeeds, (command, result.stdout, result.stderr)
            return result

        def verify():
            owned = {}
            for profile in profiles:
                with Codex(codex, profile) as client:
                    hooks = client.hooks()
                own = [h for h in hooks if "codewindow-report" in h.get("command", "")]
                assert len(own) == 8, own
                assert all(h["trustStatus"] == "trusted" for h in own)
                user = next(h for h in hooks if h["command"] == "/usr/bin/true")
                assert user["currentHash"] == preserved[profile]["currentHash"]
                assert user["trustStatus"] == "trusted" and user["enabled"] is False
                other = next(h for h in hooks if h["command"] == "/usr/bin/false")
                assert other["trustStatus"] == "untrusted" and other["enabled"] is True
                owned[profile] = own
            return owned

        result = install("install")
        assert "/hooks" not in result.stdout
        owned = verify()
        install("status")
        print("PASS setup trusts only CodeWindow hooks in every Codex profile")

        original_configs = {p: (p / "config.toml").read_bytes() for p in profiles}
        install("install")
        install("refresh")
        assert all((p / "config.toml").read_bytes() == original_configs[p] for p in profiles)
        print("PASS repeated setup leaves config and existing hook choices unchanged")

        profile = profiles[0]
        hook = owned[profile][0]
        with Codex(codex, profile) as client:
            client.write([{
                "keyPath": "hooks.state." + json.dumps(hook["key"]),
                "value": {"trusted_hash": "sha256:outdated", "enabled": False},
                "mergeStrategy": "upsert",
            }])
        install("status", succeeds=False)
        install("refresh")
        refreshed = verify()
        assert next(h for h in refreshed[profile] if h["key"] == hook["key"])["enabled"] is False
        print("PASS refresh repairs old trust without enabling a disabled hook")

        # Disabling an untrusted hook creates state without a trusted_hash.
        # Uninstall must remove it too, or a fresh install stays disabled.
        with Codex(codex, profile) as client:
            client.write([{
                "keyPath": "hooks.state." + json.dumps(hook["key"]),
                "value": {"enabled": False},
                "mergeStrategy": "replace",
            }])

        install("uninstall")
        install("status", succeeds=False)
        install("refresh")
        for profile in profiles:
            with Codex(codex, profile) as client:
                remaining = client.hooks()
                state = client.request("config/read", {})["config"].get("hooks", {}).get("state", {})
            assert len(remaining) == 2
            assert not any("codewindow-report" in h.get("command", "") for h in remaining)
            config = (profile / "config.toml").read_text()
            assert 'model = "keep-me"' in config
            assert preserved[profile]["currentHash"] in config
            assert all(h["currentHash"] not in config for h in owned[profile])
            assert all(h["key"] not in state for h in owned[profile])
        print("PASS uninstall removes CodeWindow trust and preserves other hooks")

        install("install")
        reinstalled = verify()
        assert all(h["enabled"] for hooks in reinstalled.values() for h in hooks)
        print("PASS reinstall enables hooks after removing untrusted disabled settings")

        (profiles[0] / "config.toml").write_text("invalid = [\n")
        result = install("install", succeeds=False)
        assert "Agents connected" not in result.stdout
        print("PASS invalid Codex configuration reports setup failure")

        # A CLI that exits early must produce an installer error, not SIGPIPE.
        fake_cli = Path(temporary) / "codex"
        fake_cli.write_text("#!/bin/sh\nexit 0\n")
        fake_cli.chmod(0o755)
        result = subprocess.run(
            [str(helper), "install", "--home", str(home)],
            env=dict(os.environ, PATH=temporary + os.pathsep + os.environ.get("PATH", ""), CODEWINDOW_DISABLE_ANALYTICS="1"),
            capture_output=True, text=True, timeout=20,
        )
        assert result.returncode == 1, (result.returncode, result.stderr)
        assert "Agents connected" not in result.stdout
        print("PASS a disconnected Codex process produces a recoverable setup error")

        install("uninstall")
        assert not (home / "Library/Application Support/CodeWindow").exists()
        assert "codewindow-report" not in (profiles[0] / "hooks.json").read_text()
        with Codex(codex, profiles[1]) as client:
            state = client.request("config/read", {})["config"].get("hooks", {}).get("state", {})
        assert all(h["key"] not in state for h in reinstalled[profiles[1]])
        print("PASS hooks can be removed even when Codex configuration is invalid")


if __name__ == "__main__":
    executable = shutil.which("codex")
    assert executable, "A Codex CLI with hooks/list support is required"
    check(Path(sys.argv[1]).resolve(), executable)
