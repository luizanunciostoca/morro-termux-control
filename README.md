# Morro Termux Control

Private control plane for persistent command execution on the Morro Digital Android/Termux workstation.

## Architecture

```
ChatGPT
   |
GitHub connector
   |
luizanunciostoca/morro-termux-control (private)
   |
GitHub Actions
   |
self-hosted ARM64 runner
   |
Debian / PRoot
   |
Termux / Android (SM-X820)
```

## What this provides

- Persistent GitHub-controlled runner on the tablet.
- Automatic restart if the runner process exits.
- Automatic startup after Android reboot through Termux:Boot.
- Serialized command execution.
- Per-job timeout.
- Captured stdout, stderr, exit code and timestamps.
- GitHub Actions artifacts for execution evidence.
- Local start/stop/restart/status/log controls.
- No dependency on Remote Desktop Commander for normal shell execution.

## Execution boundary

Only an authenticated push by `luizanunciostoca` to `main` that adds or changes:

```
jobs/requests/*.json
```

can execute a command.

Pull requests do not execute shell commands on the tablet.

## Job schema

```json
{
  "version": 1,
  "id": "unique-job-id",
  "description": "What this job is expected to do",
  "cwd": "~",
  "timeout_seconds": 900,
  "command": "pwd; git status"
}
```

Maximum command timeout: 3600 seconds.

## Setup

See [docs/SETUP.md](docs/SETUP.md).

## Security

See [SECURITY.md](SECURITY.md).

This bridge does not grant Android root privileges. Commands run with the permissions actually available to Debian/PRoot, Termux and any separately authorized local interfaces such as ADB or Termux:API.
