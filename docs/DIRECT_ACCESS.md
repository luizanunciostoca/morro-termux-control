# Direct tablet access — Remote Desktop Commander

## Canonical direct transport

Validated path on the current tablet:

```text
ChatGPT
  -> Remote Desktop Commander MCP
  -> paired Remote Device
  -> termux-services / runit: desktop-commander
  -> Termux shell / filesystem / processes
```

No GitHub Issue is used for commands on this path. Native Agent V3 remains the fallback.

## Validated runtime

```text
Tablet: Samsung SM-X820
Android: 16
Termux: Google Play googleplay.2026.06.21
Desktop Commander: 0.2.51
Supervisor: termux-services / runit
```

Version 0.2.51 is intentionally pinned on this tablet because direct `start_process` was proven after restart. A parallel 0.2.52 launcher was observed to fail process spawning in this Termux environment and must not run alongside the canonical service.

## Installation / repair

```bash
cd "$HOME/morro-termux-control"
git fetch origin main
git switch main
git merge --ff-only origin/main
bash scripts/install-direct-commander.sh
```

Pair only if the installer reports `PAIR_REQUIRED`.

## Boot persistence

This tablet uses the Google Play Termux build. In that distribution, the former Termux:Boot functionality is integrated into the main Termux app; a separate `com.termux.boot` application is not required.

Canonical hook:

```text
~/.termux/boot/10-morro-remote-commander.sh
```

It starts termux-services and enables the runit `desktop-commander` service. Runit provides process supervision.

## Android Wireless Debugging / ADB

Wireless debugging is enabled and the local Termux ADB client is already paired.

Validated:

```text
adb: installed
device: SM-X820
Android: 16
adb shell: uid=2000(shell)
```

The displayed Wi-Fi debugging endpoint is ephemeral. Never hardcode it in source control.

```bash
adb connect <current-ip:port>
adb devices -l
adb shell id
```

ADB provides Android shell authority, not kernel root.

## Background persistence

Applied through ADB to `com.termux`:

```text
device-idle whitelist: enabled
RUN_IN_BACKGROUND: allow
RUN_ANY_IN_BACKGROUND: allow
```

No separate `com.termux.boot` package exists in this Google Play installation.

## Acceptance

Passed:

- direct device online;
- ping;
- direct Termux shell;
- direct filesystem create/read/delete;
- Debian/PRoot command;
- wireless ADB + Android shell;
- controlled runit service restart;
- automatic reconnect after service restart;
- direct shell works after reconnect.

Final persistence proof passed on 2026-10-01:

- Android reboot completed;
- Remote Desktop Commander returned online automatically;
- post-reboot `ping` succeeded;
- post-reboot direct Termux shell returned `POST_REBOOT_DIRECT_OK`;
- post-reboot filesystem create/read/delete passed;
- post-reboot Debian/PRoot returned `POST_REBOOT_DEBIAN_OK`;
- Native Agent heartbeat returned with a new boot ID and fresh instance;
- Native Agent issue #569 executed after reboot with `exit_code: 0` and returned `POST_REBOOT_FALLBACK_OK`.

The direct access architecture is therefore accepted for normal operation. Keep Native Agent V3 enabled as the fallback channel.


## Post-reboot ADB note

After an Android reboot, the local ADB server may not be running and the Wireless Debugging TCP endpoint may have changed. This does not affect the direct Commander transport or Native Agent fallback.

When starting the Termux ADB client, use the Termux temp directory if needed:

```bash
export TMPDIR="$PREFIX/tmp"
adb start-server
```

Then connect using the **current** endpoint shown under Android Developer Options > Wireless debugging:

```bash
adb connect <current-ip:port>
adb devices -l
```

Do not treat a disconnected ADB client as loss of Termux remote access.
