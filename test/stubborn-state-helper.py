import os
import signal
import sys
import time
from pathlib import Path


pid_path = Path(sys.argv[2]).parent / "stubborn-state-helper.pid"
pid_path.write_text(str(os.getpid()), encoding="ascii")
signal.signal(signal.SIGTERM, signal.SIG_IGN)
while True:
    time.sleep(1)
