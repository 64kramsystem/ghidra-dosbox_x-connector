from __future__ import annotations

import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]


def free_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def test_live_qmp_and_gdb(tmp_path: Path) -> None:
    dosbox_path = os.environ.get("DOSBOX_X_PATH")
    dos_mcp_root = os.environ.get("DOS_MCP_ROOT")
    if not dosbox_path or not dos_mcp_root:
        pytest.skip("set DOSBOX_X_PATH and DOS_MCP_ROOT for the live smoke test")

    sys.path.insert(0, str(Path(dos_mcp_root) / "src"))
    from dos_mcp.qmp import QmpClient
    from dos_mcp.tools import pause, read_memory, resume, status, swap_floppy

    gdb_port = free_port()
    qmp_port = free_port()
    log_path = tmp_path / "dosbox-x.log"
    environment = os.environ.copy()
    environment["SDL_AUDIODRIVER"] = "dummy"

    command = [
        "xvfb-run",
        "-a",
        dosbox_path,
        "-conf",
        str(ROOT / "data/dosbox-x-malware.conf"),
        "-set",
        f"dosbox gdbserver port={gdb_port}",
        "-set",
        f"dosbox qmpserver port={qmp_port}",
        "-noautoexec",
    ]
    with log_path.open("wb") as log:
        process = subprocess.Popen(
            command,
            stdout=log,
            stderr=subprocess.STDOUT,
            env=environment,
            start_new_session=True,
        )
        try:
            client = QmpClient(qmp_port, 1)
            deadline = time.monotonic() + 15
            while True:
                if process.poll() is not None:
                    pytest.fail(f"DOSBox-X exited early; see {log_path}")
                try:
                    status(client)
                    break
                except RuntimeError:
                    if time.monotonic() >= deadline:
                        pytest.fail(f"QMP did not become ready; see {log_path}")
                    time.sleep(0.1)

            assert pause(client)["status"] == "paused"
            memory = read_memory(client, 0xFFFF0, 16)
            assert memory["size"] == 16
            assert memory["consistent"] is True
            assert resume(client)["status"] == "running"
            assert swap_floppy(client, drive=0) == {"ok": True, "drive": 0}

            gdb = subprocess.run(
                [
                    "gdb",
                    "-q",
                    "-nx",
                    "-batch",
                    "-ex",
                    "set architecture i8086",
                    "-ex",
                    f"target remote 127.0.0.1:{gdb_port}",
                    "-ex",
                    "info registers",
                    "-ex",
                    "x/16bx 0xffff0",
                    "-ex",
                    "stepi",
                    "-ex",
                    "detach",
                ],
                text=True,
                capture_output=True,
                timeout=15,
            )
            assert gdb.returncode == 0, gdb.stdout + gdb.stderr
            assert "cs" in gdb.stdout
            assert "0xffff0" in gdb.stdout
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
