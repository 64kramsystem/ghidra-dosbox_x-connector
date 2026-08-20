#!/usr/bin/env bash
#@title DOSBox-X DOS Debugger
#@desc <html><body width="300px">
#@desc   <h3>Launch DOSBox-X and connect Ghidra through GDB</h3>
#@desc   <p>Uses the x86 real-mode language and loopback-only debug ports.</p>
#@desc </body></html>
#@menu-group gdb
#@icon icon.debugger
#@help gdb#remote
#@depends Debugger-rmi-trace
#@depends Debugger-agent-gdb
#@env OPT_DOSBOX_X_PATH:file="dosbox-x" "DOSBox-X command" "Patched DOSBox-X executable. Omit the full path to resolve it with PATH."
#@env OPT_DOSBOX_X_CONF:file="" "Guest config" "Optional DOSBox-X configuration loaded after the isolated base configuration."
#@env OPT_BOOT_IMAGE:file="" "Boot image" "Optional bootable floppy image. The image remains writable."
#@env OPT_HDD_IMAGE:file="" "Hard-disk image" "Optional bootable raw hard-disk image. The image remains writable."
#@env OPT_HDD_GEOMETRY:str="512,63,2,520" "Hard-disk geometry" "Sector size, sectors, heads, and cylinders passed to IMGMOUNT -size."
#@env OPT_EXTRA_DOSBOX_X_ARGS:str="" "Extra DOSBox-X arguments" "Additional arguments passed to DOSBox-X. Use with care."
#@env OPT_GDB_PATH:file="gdb" "GDB command" "GDB with i8086 architecture support. Omit the full path to resolve it with PATH."
#@env OPT_GDB_ARGS:str="" "GDB arguments" "Additional arguments passed to GDB."
#@env DOSBOX_X_GDB_PORT:int=2159 "GDB port" "Loopback GDB remote-protocol port."
#@env DOSBOX_X_QMP_PORT:int=4444 "QMP port" "Loopback QMP port used by dos-mcp."

set -euo pipefail

. "$MODULE_Debugger_rmi_trace_HOME/data/support/setuputils.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_CONF="$EXT_ROOT/data/dosbox-x-malware.conf"

pypath_trace=$(ghidra-module-pypath "Debugger-rmi-trace")
pypath_gdb=$(ghidra-module-pypath "Debugger-agent-gdb")
export PYTHONPATH="$pypath_gdb:$pypath_trace:${PYTHONPATH:-}"
export SDL_VIDEODRIVER=dummy
export SDL_AUDIODRIVER=dummy

if [[ -n "$OPT_BOOT_IMAGE" && -n "$OPT_HDD_IMAGE" ]]; then
    echo "Choose either a floppy boot image or a hard-disk image, not both" >&2
    exit 2
fi
if [[ -n "$OPT_HDD_IMAGE" && ! "$OPT_HDD_GEOMETRY" =~ ^[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]]; then
    echo "Hard-disk geometry must be size,sectors,heads,cylinders" >&2
    exit 2
fi

dosbox_args=(-conf "$BASE_CONF")
if [[ -n "$OPT_DOSBOX_X_CONF" ]]; then
    dosbox_args+=(-conf "$OPT_DOSBOX_X_CONF")
fi
dosbox_args+=(
    -set "dosbox gdbserver=true"
    -set "dosbox gdbserver port=$DOSBOX_X_GDB_PORT"
    -set "dosbox qmpserver=true"
    -set "dosbox qmpserver port=$DOSBOX_X_QMP_PORT"
    -set "cpu core=normal"
    -set "dos share=false"
    -set "dos network redirector=false"
    -set "dos automount=false"
    -set "dos automountall=false"
    -set "dos startcmd=false"
    -set "dos dos clipboard device enable=false"
    -set "dos dos clipboard api=false"
    -set "serial serial1=disabled"
    -set "serial serial2=disabled"
    -set "serial serial3=disabled"
    -set "serial serial4=disabled"
    -set "parallel parallel1=disabled"
    -set "parallel parallel2=disabled"
    -set "parallel parallel3=disabled"
    -set "ipx ipx=false"
    -set "ne2000 ne2000=false"
)
if [[ -n "$OPT_EXTRA_DOSBOX_X_ARGS" ]]; then
    # Ghidra exposes this field as one shell-style word list, matching its
    # standard GDB and QEMU launchers.
    dosbox_args+=($OPT_EXTRA_DOSBOX_X_ARGS)
fi
if [[ -n "$OPT_BOOT_IMAGE" ]]; then
    dosbox_args+=(-c "IMGMOUNT A \"$OPT_BOOT_IMAGE\" -t floppy" -c "BOOT A:")
fi
if [[ -n "$OPT_HDD_IMAGE" ]]; then
    dosbox_args+=(
        -c "IMGMOUNT 2 \"$OPT_HDD_IMAGE\" -t hdd -fs none -size $OPT_HDD_GEOMETRY"
        -c "BOOT C:"
    )
fi

"$OPT_DOSBOX_X_PATH" "${dosbox_args[@]}" &
dosbox_pid=$!
cleanup() {
    kill "$dosbox_pid" 2>/dev/null || true
    wait "$dosbox_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Probe readiness without leaving a helper process behind. The GDB server
# accepts the short probe, observes its close, and is ready for GDB after the
# additional delay.
ready=false
for _ in {1..100}; do
    if ! kill -0 "$dosbox_pid" 2>/dev/null; then
        echo "DOSBox-X exited before opening its GDB port" >&2
        exit 1
    fi
    if (: >"/dev/tcp/127.0.0.1/$DOSBOX_X_GDB_PORT") 2>/dev/null; then
        ready=true
        sleep 0.1
        break
    fi
    sleep 0.1
done
if [[ "$ready" != true ]]; then
    echo "DOSBox-X did not open GDB port $DOSBOX_X_GDB_PORT" >&2
    exit 1
fi

gdb_args=(
    "$OPT_GDB_PATH"
    -q
    -ex "set pagination off"
    -ex "set confirm off"
    -ex "python import ghidragdb"
    -ex "python if not 'ghidragdb' in locals(): exit(253)"
    -ex "set architecture i8086"
    -ex "set endian little"
    -ex "set ghidra-language x86:LE:16:Real Mode"
    -ex "set ghidra-compiler default"
)
if [[ -n "$OPT_GDB_ARGS" ]]; then
    gdb_args+=($OPT_GDB_ARGS)
fi
gdb_args+=(
    -ex "target remote 127.0.0.1:$DOSBOX_X_GDB_PORT"
    -ex "ghidra trace connect '$GHIDRA_TRACE_RMI_ADDR'"
    -ex "ghidra trace start"
    -ex "ghidra trace sync-enable"
    -ex "ghidra trace sync-synth-stopped"
    -ex "set confirm on"
)

"${gdb_args[@]}"
