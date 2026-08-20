from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_launcher_syntax() -> None:
    subprocess.run(
        ["bash", "-n", "data/debugger-launchers/dosbox-x-gdb.sh"],
        cwd=ROOT,
        check=True,
    )


def test_debug_services_are_loopback_only() -> None:
    launcher = (ROOT / "data/debugger-launchers/dosbox-x-gdb.sh").read_text()
    assert "target remote 127.0.0.1:" in launcher
    assert "0.0.0.0" not in launcher


def test_isolated_config_disables_host_bridges() -> None:
    config = (ROOT / "data/dosbox-x-malware.conf").read_text()
    for setting in (
        "share = false",
        "automount = false",
        "startcmd = false",
        "dos clipboard api = false",
        "ipx = false",
        "ne2000 = false",
        "serial1 = disabled",
        "parallel1 = disabled",
    ):
        assert setting in config

