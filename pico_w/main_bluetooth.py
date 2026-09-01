"""Compatibility filename. Copy pico_w/main.py onto the Pico as main.py (Thonny).

This shim re-exports the sibling main.py so both repo paths stay in lockstep.
Do not save this file on the Pico as main.py — that would shadow the boot file.
"""

import os
import sys

_dir = os.path.dirname(__file__) or "."
if _dir not in sys.path:
    sys.path.insert(0, _dir)

import main as _fw  # noqa: E402

for _name in dir(_fw):
    if _name.startswith("__"):
        continue
    globals()[_name] = getattr(_fw, _name)

if __name__ == "__main__":
    _fw.main()
