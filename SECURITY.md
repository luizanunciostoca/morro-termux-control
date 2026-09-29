# Security Model

This repository intentionally controls a machine with broad local shell access. Treat write access as equivalent to terminal access on the registered runner.

## Trust boundary

Accepted execution path:

1. authenticated push by `luizanunciostoca`;
2. branch `main`;
3. changed file matching `jobs/requests/*.json`;
4. schema validation by `scripts/exec-job.sh`;
5. execution on the runner labeled `morro-termux`.

Pull requests, forks and arbitrary GitHub events are not command execution sources.

## Mandatory rules

- Keep this repository private.
- Do not add untrusted collaborators.
- Never commit GitHub runner registration tokens, PATs, passwords, API keys or Android secrets.
- Never configure this runner for public repositories.
- Keep the Android lock screen and device encryption enabled.
- Revoke/remove the runner from GitHub immediately if the tablet is lost or compromised.

## Local kill switch

From Termux:

```bash
cd "$HOME/morro-termux-control"
bash scripts/termux-runnerctl.sh stop
```

The stop operation creates a local stop marker and terminates the runner process. The boot wrapper can be removed from:

```
$HOME/.termux/boot/10-morro-github-runner
```

## Scope

The bridge does not create Android root privileges. It can only perform operations available to the Termux/PRoot user and any separately authorized interfaces such as ADB, Shizuku or Termux:API.
