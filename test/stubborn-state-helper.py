import os
import signal
import sys
import time
from pathlib import Path


config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
pid_path = config_home / "omarchy" / "one-bit-bureau" / "stubborn-state-helper.pid"
pid_path.write_text(str(os.getpid()), encoding="ascii")
signal.signal(signal.SIGTERM, signal.SIG_IGN)
while True:
    time.sleep(1)
