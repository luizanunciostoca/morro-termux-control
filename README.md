# Morro Termux Control

> **ChatGPT/operator:** read [CHATGPT-START-HERE.md](CHATGPT-START-HERE.md) first. It is the durable contract for using the persistent Termux/Debian bridge from any new chat.

Private control plane for persistent command execution on the Morro Digital Android/Termux workstation.

## Preferred architecture — Native Termux Agent V2

```
ChatGPT
   |
GitHub connector
   |
private GitHub issue: [TERMUX-JOB]
   |
native Bash agent in Termux
   |
Termux or Debian/PRoot
   |
result comment + issue close
```

This is the preferred transport for Android ARM64 because it does not depend on the official GitHub Actions runner or its embedded .NET/CoreCLR runtime.

## Capabilities

- persistent command polling through the private GitHub repository;
- direct Termux execution;
- Debian/PRoot execution;
- explicit request schema and owner verification;
- per-command timeout;
- stdout/stderr capture;
- local completion markers;
- duplicate-execution protection after interrupted jobs;
- GitHub issue result/audit trail;
- remote heartbeat issue;
- local start/stop/restart/status/log controls.

## Job format

Issue title:

`[TERMUX-JOB] descriptive title`

Issue body:

```json
{
  "version": 2,
  "confirm": "EXECUTE",
  "id": "unique-job-id",
  "target": "termux",
  "cwd": "~",
  "timeout_seconds": 900,
  "command": "pwd; git status"
}
```

Target may be `termux` or `debian`.

### Pre-dispatch integrity

Construct the issue body with a real JSON serializer, never by manual string interpolation. The `Native Agent Job Preflight` workflow validates and canonicalizes the exact issue body and posts a `MORRO_JOB_PREFLIGHT_V3` attestation containing its SHA-256. The tablet agent refuses to claim or execute a request unless a matching attestation from `github-actions[bot]` exists. Editing the body invalidates the old attestation. Invalid JSON is fail-closed before execution.

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

See [docs/NATIVE_AGENT.md](docs/NATIVE_AGENT.md).

## Legacy Actions Runner

The original GitHub Actions self-hosted runner implementation remains in repository history for reference, but is not the preferred Android transport.

## Security

The repository must remain private. The native agent only accepts jobs authored by `luizanunciostoca`, with the required title prefix, schema version, explicit execution confirmation, supported target, and bounded timeout.

This bridge does not grant Android root privileges. Commands run only with permissions already available to Termux, Debian/PRoot, and separately authorized interfaces such as ADB or Termux:API.
