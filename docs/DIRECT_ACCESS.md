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

The authenticated device session is expected at:

```text
~/.desktop-commander-device/device.json
```

That credential file stays local to the tablet.

## One-time bootstrap

From Termux:

```bash
cd "$HOME/morro-termux-control"
git fetch origin main
git switch main
git merge --ff-only origin/main
bash scripts/install-direct-commander.sh
```

If an existing saved device session is present, the installer starts the supervisor automatically.

If the installer reports `direct_access=PAIR_REQUIRED`, run:

```bash
bash scripts/termux-remote-commanderctl.sh pair
```

The pairing command is interactive. Keep it open until the CLI reports `Device ready`. Complete the browser/device-flow authorization if requested.

After `Device ready`, press `Ctrl+C` once to stop the foreground pairing process. The saved session remains on disk. Then activate persistent mode by running the installer again:

```bash
bash scripts/install-direct-commander.sh
bash scripts/termux-remote-commanderctl.sh status
```

Do not run a background Remote Device before pairing; the controller intentionally refuses background startup when the saved session is missing.

## Boot persistence

`scripts/install-direct-commander.sh` installs:

```text
~/.termux/boot/10-morro-remote-commander.sh
```

That boot hook starts:

```text
scripts/termux-remote-commander-supervisor.sh
```

The supervisor checks the remote device process every 60 seconds and restarts it when needed.

## Operations

```bash
bash scripts/termux-remote-commanderctl.sh status
bash scripts/termux-remote-commanderctl.sh restart
bash scripts/termux-remote-commanderctl.sh logs
```

## Acceptance

The direct path is accepted only after all of the following are observed:

1. Remote Desktop Commander reports the tablet online.
2. ChatGPT can ping the tablet.
3. ChatGPT can run a read-only shell probe.
4. ChatGPT can create and delete a temporary file under the Termux home directory.
5. The device agent reconnects after a controlled restart.
6. The device agent reconnects after Android reboot.

Until those checks pass, do not retire the GitHub Native Agent fallback.


## Android Wireless Debugging / ADB layer

When Android **Wireless debugging** is enabled and the tablet has already been paired with the local Termux ADB client, the direct Commander path can invoke `adb shell` for Android-shell operations that are not available to the ordinary Termux app UID.

Observed/validated on the current tablet:

```text
device model: SM-X820
Android: 16
Termux ADB client: installed
ADB shell identity: uid=2000(shell)
```

The Wi-Fi debugging host/port is session-specific and may change after toggling Wireless debugging, changing networks, or rebooting. Never hardcode the current endpoint in source control. Use the endpoint displayed by Android at runtime, then verify with:

```bash
adb connect <ip:port>
adb devices -l
adb shell id
```

This ADB layer increases Android administration capability but is not Android root.
