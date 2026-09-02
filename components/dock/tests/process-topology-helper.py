#!/usr/bin/python3

"""Create a nested, TERM-ignoring Linux process topology for runner tests."""

from __future__ import annotations

import json
import os
import signal
import sys
import time
from pathlib import Path


def record(pid: int) -> dict[str, int]:
    return {
        "pid": pid,
        "ppid": os.getppid() if pid == os.getpid() else os.getpid(),
        "pgid": os.getpgid(pid),
        "sid": os.getsid(pid),
    }


def main() -> None:
    output = Path(sys.argv[1])
    ready_read, ready_write = os.pipe()
    child = os.fork()
    if child == 0:
        os.close(ready_read)
        os.setsid()
        payload = (json.dumps(record(os.getpid()), sort_keys=True) + "\n").encode()
        os.write(ready_write, payload)
        os.close(ready_write)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        time.sleep(60)
        return

    os.close(ready_write)
    raw = os.read(ready_read, 4096)
    os.close(ready_read)
    topology = {
        "parent": record(os.getpid()),
        "child": json.loads(raw.decode("utf-8")),
    }
    output.write_text(json.dumps(topology, sort_keys=True) + "\n", encoding="utf-8")
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(60)


if __name__ == "__main__":
    main()
