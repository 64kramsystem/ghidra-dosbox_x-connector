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


def test_launcher_is_headless_and_supports_raw_hard_disks() -> None:
    launcher = (ROOT / "data/debugger-launchers/dosbox-x-gdb.sh").read_text()
    assert "export SDL_VIDEODRIVER=dummy" in launcher
    assert "export SDL_AUDIODRIVER=dummy" in launcher
    assert '#@env OPT_HDD_IMAGE:file=""' in launcher
    assert '#@env OPT_HDD_GEOMETRY:str="512,63,2,520"' in launcher
    assert 'IMGMOUNT 2 \\"$OPT_HDD_IMAGE\\" -t hdd -fs none -size $OPT_HDD_GEOMETRY' in launcher
    assert '-c "BOOT C:"' in launcher


def test_isolated_config_disables_host_bridges() -> None:
    config = (ROOT / "data/dosbox-x-malware.conf").read_text()
    for setting in (
        "quit warning = false",
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
