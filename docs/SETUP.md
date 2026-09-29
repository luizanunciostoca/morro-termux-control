# Setup — Morro Termux Persistent Runner

## Architecture

ChatGPT -> GitHub private repository -> GitHub Actions -> self-hosted ARM64 runner -> Debian/PRoot -> Termux/Android.

Only pushes to `main` that add/change `jobs/requests/*.json` are executable. Pull requests do not run commands on the tablet.

## Requirements

- Termux installed from a trusted source.
- Debian installed with `proot-distro`.
- Termux:Boot installed from the same package source family as Termux.
- Internet connectivity.
- GitHub repository administrator access.

## 1. Prepare Termux

Run outside Debian:

```bash
pkg update -y
pkg upgrade -y
pkg install -y git gh proot-distro termux-api
termux-wake-lock
```

Authenticate GitHub if needed:

```bash
gh auth status || gh auth login
```

Clone the private control repository:

```bash
cd "$HOME"
rm -rf morro-termux-control
gh repo clone luizanunciostoca/morro-termux-control
cd morro-termux-control
git checkout main
git pull --ff-only
chmod +x scripts/*.sh
```

## 2. Get the temporary runner token

In GitHub:

Repository -> Settings -> Actions -> Runners -> New self-hosted runner.

Choose:

- Linux
- ARM64

Copy the temporary registration token from the `config.sh` command.

Do not commit or paste that token into the repository.

## 3. Bootstrap inside Debian

From Termux:

```bash
proot-distro login debian
```

Inside Debian, make the Termux repository visible by cloning it again:

```bash
apt-get update
apt-get install -y git gh
gh auth status || gh auth login
cd /root
rm -rf morro-termux-control
gh repo clone luizanunciostoca/morro-termux-control
cd morro-termux-control
git checkout main
git pull --ff-only
chmod +x scripts/*.sh
```

Register the runner using the temporary token:

```bash
RUNNER_TOKEN='PASTE_TEMPORARY_TOKEN_HERE' \
  bash scripts/bootstrap-debian-runner.sh
```

The script resolves the latest GitHub Actions ARM64 runner dynamically, installs dependencies, verifies the GitHub asset digest when the API exposes one, configures labels, and creates the local restart loop.

Test interactively:

```bash
cd /root/morro-actions-runner
./runner-loop.sh
```

When GitHub reports the runner as Online, stop the foreground test with Ctrl+C.

## 4. Install persistent boot on the Termux side

Exit Debian:

```bash
exit
```

Back in Termux:

```bash
cd "$HOME/morro-termux-control"
bash scripts/install-termux-boot.sh
bash scripts/termux-runnerctl.sh start
bash scripts/termux-runnerctl.sh status
```

## 5. Android/Samsung background settings

Open Termux:Boot at least once after installation.

For both Termux and Termux:Boot:

- Settings -> Apps -> app -> Battery -> Unrestricted.
- Settings -> Battery / Device care -> Background usage limits -> Never sleeping apps -> add the app.
- Do not use Force stop while the persistent runner is expected to remain online.

## 6. Validate from GitHub

Repository -> Settings -> Actions -> Runners.

Expected runner:

- Name: `morro-sm-x820`
- Status: Online
- Labels: `self-hosted`, `Linux`, `ARM64`, `morro-termux`, `sm-x820`, `debian-proot`

## 7. Execute a diagnostic job

Create a unique request under `jobs/requests/` using this schema:

```json
{
  "version": 1,
  "id": "doctor-001",
  "description": "First persistent runner diagnostic",
  "cwd": "~",
  "timeout_seconds": 120,
  "command": "uname -a; id; pwd; git --version; node --version || true"
}
```

Push it directly to `main`.

The workflow captures:

- stdout
- stderr
- exit code
- timestamps
- duration
- an Actions artifact named `morro-termux-results`

## 8. Local operations

Outside Debian, in Termux:

```bash
cd "$HOME/morro-termux-control"
bash scripts/termux-runnerctl.sh status
bash scripts/termux-runnerctl.sh restart
bash scripts/termux-runnerctl.sh logs
bash scripts/termux-runnerctl.sh stop
```

## Security model

- Repository is private.
- Only pushes to `main` can reach the runner.
- Only actor `luizanunciostoca` is accepted by the workflow.
- PR events cannot execute shell commands.
- Jobs are serialized with GitHub Actions concurrency.
- Each individual command has a maximum timeout of 3600 seconds.
- Job results are retained as Actions artifacts for 30 days.
- The runner is limited to the actual permissions of Debian/PRoot/Termux/Android.
