# Ghidra DOSBox-X Connector

A small Ghidra debugger extension for 16-bit DOS targets. It launches a pinned,
remote-debug-enabled DOSBox-X build, connects Ghidra's maintained GDB TraceRMI
agent, and forces the trace language to `x86:LE:16:Real Mode`.

The extension deliberately contains no second debugger implementation. The
companion `dos-mcp` process owns DOSBox-X QMP automation; Ghidra owns registers,
memory, breakpoints, stepping, and the dynamic trace through its standard GDB
agent.

## Requirements

- Ghidra 12.1 and JDK 21
- GDB with the `i8086` architecture
- DOSBox-X source at tag `dosbox-x-v2026.08.02`

## Build DOSBox-X

Apply the pinned patch to a clean checkout or worktree at the supported tag:

```sh
tools/apply-dosbox-x-patch ~/local/dosbox-x/.worktrees/remotedebug
cd ~/local/dosbox-x/.worktrees/remotedebug
./build-debug-g3-sdl2 --enable-remotedebug
```

The patch adds loopback-only GDB (`2159`) and QMP (`4444`) servers. It is based
on `lokkju/dosbox-x-remotedebug` and ported to the stated official release.

## Build and install the Ghidra extension

```sh
GHIDRA_INSTALL_DIR=/path/to/ghidra ./gradlew buildExtension
```

Install the zip from `dist/` through **File > Install Extensions**, then restart
Ghidra. Choose **DOSBox-X DOS Debugger** and select the patched executable. The
launch dialog accepts an optional DOSBox-X config and either a bootable floppy
or raw hard-disk image with explicit geometry.

The launcher runs DOSBox-X with dummy SDL video/audio, enables the debug servers
on loopback, selects the normal CPU core, and disables IPX, NE2000, serial and
parallel devices, host clipboard integration, host command execution, and
automatic host-directory mounts. It never mounts a host directory. The supplied
base configuration uses a 386 prefetch model; choose the historically appropriate
CPU in a separate guest config when the target requires another model.

Use disposable copies of writable disk images. Malware can modify every image
attached to the guest, and snapshots do not make an attached base image
immutable.

GPL-2.0-or-later.
