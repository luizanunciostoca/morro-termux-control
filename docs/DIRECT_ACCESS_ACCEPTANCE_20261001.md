# Direct Access Acceptance — 2026-10-01

## Scope

Final acceptance of the persistent, non-GitHub primary access path to the Morro Digital Android/Termux tablet, with Native Termux Agent V3 retained as independent fallback.

## Device/runtime

```text
Tablet: Samsung SM-X820
Android: 16
Termux: Google Play googleplay.2026.06.21
Direct transport: Remote Desktop Commander
Validated Commander runtime: 0.2.51
Supervisor: termux-services / runit
Fallback: Native Termux Agent V3 over GitHub Issues
```

## Direct transport evidence

Passed:

- device listed Online;
- MCP ping returned pong;
- direct Termux shell returned `DIRECT_051_SHELL_OK`;
- direct filesystem create/read/delete passed;
- Debian/PRoot execution passed;
- controlled runit restart produced a new Commander process and reconnected;
- direct shell after controlled restart returned `POST_ABS_RESTART_DIRECT_OK`.

## Android reboot evidence

After a physical Android reboot:

- the kernel boot ID changed, proving a new boot session;
- Remote Desktop Commander returned Online without manual pairing;
- post-reboot ping succeeded;
- direct shell returned `POST_REBOOT_DIRECT_OK`;
- canonical repository HEAD remained `43b7e27f3f8ef0b61efd63e3251feb969d33e10c` at the time of proof;
- runit reported the `desktop-commander` service running;
- direct post-reboot filesystem create/read/delete passed;
- Debian/PRoot returned `POST_REBOOT_DEBIAN_OK`;
- Native Agent heartbeat returned with the same new boot ID;
- fallback job #569 returned `POST_REBOOT_FALLBACK_OK` with `exit_code: 0`.

The boot ID and commit above are historical acceptance evidence only, not future authority.

## ADB layer

Wireless debugging was also validated before reboot:

- Termux ADB client installed;
- connected to the tablet;
- device identified as SM-X820;
- Android shell identity was `uid=2000(shell)`.

The Wireless Debugging endpoint is ephemeral and must not be hardcoded.

## Decision

```text
DIRECT_COMMANDER_PRIMARY = ACCEPTED
NATIVE_AGENT_FALLBACK = ACCEPTED
POST_REBOOT_PERSISTENCE = PASS
MANUAL_PAIRING_AFTER_REBOOT = NOT_REQUIRED
```

Future sessions must check live state first and use direct Commander when healthy.
