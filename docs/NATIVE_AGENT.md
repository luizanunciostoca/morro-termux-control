# Native Termux Agent V2

Preferred persistent transport for the Morro Digital Android tablet.

## Transport

ChatGPT -> GitHub connector -> private GitHub issue -> native Bash agent in Termux -> Termux or Debian/PRoot -> result comment -> issue closed.

This design does not depend on the official GitHub Actions self-hosted runner or its embedded .NET/CoreCLR runtime.

## Request format

Issue title:

`[TERMUX-JOB] descriptive title`

Issue body:

```json
{
  "version": 2,
  "confirm": "EXECUTE",
  "id": "doctor-001",
  "target": "termux",
  "cwd": "~",
  "timeout_seconds": 120,
  "command": "uname -a; id; pwd"
}
```

Targets: `termux` or `debian`.

## Security boundaries

The agent requires a private repository owned by `luizanunciostoca`, an issue authored by `luizanunciostoca`, the exact job title prefix, schema version 2, explicit `confirm: EXECUTE`, and a timeout between 1 and 3600 seconds.

Every accepted job is marked complete locally before publishing the result, reducing accidental re-execution after network failures.

## Local controls

```bash
cd "$HOME/morro-termux-control"
bash scripts/termux-native-agentctl.sh start
bash scripts/termux-native-agentctl.sh status
bash scripts/termux-native-agentctl.sh once
bash scripts/termux-native-agentctl.sh restart
bash scripts/termux-native-agentctl.sh stop
bash scripts/termux-native-agentctl.sh logs
```

The agent maintains an open GitHub issue named `[TERMUX-AGENT] status` as its remote heartbeat.
