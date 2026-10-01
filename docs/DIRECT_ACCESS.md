# Direct tablet access — Remote Desktop Commander

## Goal

Provide ChatGPT a direct, non-GitHub execution path to the Android/Termux tablet.

Runtime path:

```text
ChatGPT
  -> Remote Desktop Commander MCP
  -> paired device agent
  -> Termux shell / filesystem / processes
```

GitHub Issues are not in this execution path. The Native Termux Agent V3 remains available as a fallback until the direct path is accepted.

## Current package

The bootstrap defaults to:

```text
@wonderwhy-er/desktop-commander@0.2.52
```

Override intentionally with:

```bash
export MORRO_COMMANDER_PACKAGE='@wonderwhy-er/desktop-commander@<version>'
```

## One-time bootstrap

From Termux:

```bash
cd "$HOME/morro-termux-control"
git fetch origin main
git switch main
git merge --ff-only origin/main
bash scripts/install-direct-commander.sh
bash scripts/termux-remote-commanderctl.sh pair
```

The pairing command is interactive. Keep it open until the CLI reports that the device is ready. Complete any browser/device-flow authorization that it requests.

After pairing, stop the foreground process with Ctrl+C if needed, then run:

```bash
bash scripts/termux-remote-commanderctl.sh restart
bash scripts/termux-remote-commanderctl.sh status
```

## Boot persistence

`scripts/install-direct-commander.sh` installs:

```text
~/.termux/boot/10-morro-remote-commander.sh
```

That boot hook starts:

```text
scripts/termux-remote-commander-supervisor.sh
```

The supervisor checks the remote device process every 60 seconds and restarts it if needed.

## Operations

```bash
bash scripts/termux-remote-commanderctl.sh status
bash scripts/termux-remote-commanderctl.sh restart
bash scripts/termux-remote-commanderctl.sh logs
```

## Acceptance

The direct path is considered accepted only after all of the following are observed:

1. Remote Desktop Commander reports the tablet online.
2. ChatGPT can ping the tablet.
3. ChatGPT can run a read-only shell probe.
4. ChatGPT can create and delete a temporary file under the Termux home directory.
5. The device agent reconnects after a controlled restart.
6. The device agent reconnects after Android reboot.

Until those checks pass, do not retire the GitHub Native Agent fallback.
