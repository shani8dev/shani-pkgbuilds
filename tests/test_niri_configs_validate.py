"""Every niri config this repo ships is one niri can load.

shani-desktop-niri's config.kdl had `set-column-width 50%; move-column-to-side
left;` in two binds (fc03761): an unquoted percentage and an action niri does
not have. niri refuses the whole file and starts on its built-in defaults, so
none of the desktop's keys, rules or layout applied - and nothing noticed.

Runs `niri validate` from PATH, or in the shell's dev image (shani-shell-dev)
when niri is not installed here; skipped when neither exists.
"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
CONFIGS = sorted(p for p in ROOT.glob("shani-desktop-*/etc/niri/*.kdl"))


def _validate(path: Path) -> subprocess.CompletedProcess:
    if shutil.which("niri"):
        cmd = ["niri", "validate", "-c", str(path)]
    elif shutil.which("docker") and subprocess.run(
        ["docker", "image", "inspect", "shani-shell-dev"], capture_output=True
    ).returncode == 0:
        cmd = ["docker", "run", "--rm", "-v", f"{path.parent}:/c:ro", "shani-shell-dev",
               "niri", "validate", "-c", f"/c/{path.name}"]
    else:
        pytest.skip("no niri and no shani-shell-dev image to run it in")
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120)


def test_there_is_a_config_to_check():
    assert CONFIGS, "no shani-desktop-*/etc/niri/*.kdl found"


@pytest.mark.parametrize("path", CONFIGS, ids=lambda p: str(p.relative_to(ROOT)))
def test_niri_loads_it(path):
    r = _validate(path)
    out = r.stdout + r.stderr
    assert r.returncode == 0 and "config is valid" in out, out[-1500:]
