"""A real live-process registration for reporter tests; never bypasses production gating."""
from contextlib import contextmanager
from pathlib import Path
import selectors
import subprocess
import sys


@contextmanager
def running_app(host, state):
    process = subprocess.Popen(
        [str(host), "--app-presence-host", str(state)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            if not selector.select(10) or process.stdout.readline().strip() != b"READY":
                raise RuntimeError("App presence host did not start")
        yield process
    finally:
        if process.stdin and not process.stdin.closed:
            process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        process.stdout.close()
        process.stderr.close()


if __name__ == "__main__":
    with running_app(Path(sys.argv[1]), Path(sys.argv[2])):
        raise SystemExit(subprocess.call(sys.argv[3:]))
