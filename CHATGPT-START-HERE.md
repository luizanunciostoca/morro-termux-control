# CHATGPT START HERE — Persistent Termux Operator Contract

> This file is the durable operating contract for ChatGPT sessions that need to use the Morro Digital tablet/Termux environment.

## 1. Persistent capability exists

A persistent remote execution bridge is installed on the user's Android tablet.

Canonical control repository:

`luizanunciostoca/morro-termux-control`

Repository visibility must remain **PRIVATE**.

The preferred transport is **not** Remote Desktop Commander and is **not** the official GitHub Actions self-hosted runner.

The active architecture is:

```
ChatGPT
  -> GitHub connector
  -> private GitHub Issue [TERMUX-JOB]
  -> Native Termux Agent V3
  -> target: Termux or Debian/PRoot
  -> stdout/stderr/result metadata posted to the issue
  -> issue closed
```

The tablet starts the bridge automatically after Android reboot:

```
Android boot
  -> Termux:Boot
  -> ~/.termux/boot/20-morro-native-agent.sh
  -> scripts/termux-native-supervisor.sh
  -> scripts/termux-native-agent.sh daemon
```

The supervisor also restarts the agent automatically if the agent process dies.

## 2. Do not depend on Commander

The previous Commander boot hook was intentionally disabled:

```
~/.termux/boot/00-morro-remote.sh.disabled
```

The only active Morro remote-control boot hook should be:

```
~/.termux/boot/20-morro-native-agent.sh
```

Normal remote shell work should use the native GitHub-Issues bridge.

Do not ask the user to reopen or reconnect Commander for ordinary Termux/Debian command execution.

## 3. First action in a new ChatGPT session

Before issuing a remote command, check the persistent heartbeat issue:

- repository: `luizanunciostoca/morro-termux-control`
- issue title: `[TERMUX-AGENT] status`
- invariant: there must be **exactly one** open issue whose title is exactly `[TERMUX-AGENT] status`
- never trust or hardcode an issue number; enumerate all exact-title open heartbeats and use the live singleton as authority

Healthy state resembles:

```text
MORRO_NATIVE_AGENT_V3

state: ONLINE
build: native-v3
protocol_version: 2
agent_instance_id: <ephemeral instance id>
boot_id: <kernel boot id>
heartbeat_utc: <timestamp>
arch: aarch64
poll_seconds: 30
transport: GitHub Issues
targets: termux,debian
```

Treat the live issue as authority. Do not trust a cached PID, timestamp, SHA, or device state.

If the heartbeat is stale, wait at least one supervisor cycle before declaring the bridge offline. The supervisor normally checks every 60 seconds.

## 4. Creating a remote job

Create a GitHub issue in the canonical repository.

Title format:

```
[TERMUX-JOB] <short descriptive title>
```

The body must be raw JSON matching this schema:

```json
{
  "version": 2,
  "confirm": "EXECUTE",
  "id": "unique-job-id",
  "target": "termux",
  "cwd": "~",
  "timeout_seconds": 120,
  "command": "uname -a; id; pwd"
}
```

Required/allowed fields:

- `version`: must be `2`
- `confirm`: must be exactly `EXECUTE`
- `id`: unique identifier using letters, numbers, dot, underscore or hyphen
- `target`: `termux` or `debian`
- `cwd`: working directory; `~` and `~/...` are supported
- `timeout_seconds`: 1 through 3600
- `command`: shell command/script to execute

The agent only accepts jobs authored by `luizanunciostoca` in the private canonical repository.

## 5. Reading the result

Poll the job issue and its comments.

A completed job is normally closed and contains a result comment beginning with:

```
MORRO_AGENT_RESULT_V3
```

Expected result fields include:

- id
- target
- exit_code
- started_at
- ended_at
- duration_seconds
- request_sha256
- stdout
- stderr
- local evidence path

Example success condition:

```
exit_code: 0
```

Do not infer success only from the issue closing; inspect `exit_code`, `stdout`, and `stderr`.

## 6. Target semantics

### target = termux

Runs in the Android Termux userspace.

Typical available capabilities include:

- git / gh
- bash
- curl
- jq
- node/npm/pnpm when installed
- Python when installed
- Termux utilities
- proot-distro
- filesystem/process/network commands allowed by Android/Termux permissions

### target = debian

Runs inside:

- Debian GNU/Linux 13 (trixie)
- PRoot
- ARM64 / aarch64
- home: `/root`
- effective uid inside PRoot: `0`

Important: root inside PRoot is **not Android kernel root**.

## 7. Security and execution rules

The bridge is intentionally fail-closed.

Current safeguards include:

- repository must be private;
- repository owner validation;
- issue author validation;
- strict title prefix;
- schema version validation;
- explicit `confirm=EXECUTE`;
- timeout bounded to 3600 seconds;
- stdout/stderr capture;
- per-job SHA-256 evidence;
- local completed-job marker;
- claimed-job marker;
- interrupted jobs are not automatically replayed;
- supervisor recovery;
- boot persistence.

Never put passwords, PATs, registration tokens, API secrets, private keys, or other long-lived secrets directly in a job issue body.

Use the user's already-authenticated local CLIs/secrets when available.

## 8. Operational behavior for future chats

When the user asks to inspect, build, test, modify, run, deploy, diagnose, or operate something that is available through the tablet:

1. Check the live heartbeat.
2. Use the GitHub Issues bridge directly.
3. Execute the required Termux or Debian command.
4. Read the result.
5. Iterate until the requested task is complete.
6. Report concrete evidence.

For normal operations, do **not** send the user manual Termux commands first if the bridge is healthy.

Only ask for manual tablet intervention when the bridge itself is unavailable or Android requires a physical/UI action that cannot be performed through the available shell interfaces.

## 9. Recovery when heartbeat is offline

If the heartbeat becomes stale:

1. allow at least one 60-second supervisor cycle;
2. re-enumerate all open issues whose title is exactly `[TERMUX-AGENT] status` and verify singleton + freshness;
3. if still offline, the local recovery commands are:

```bash
cd "$HOME/morro-termux-control"
bash scripts/termux-native-agentctl.sh status
bash scripts/termux-native-agentctl.sh start
```

Supervisor status can be inspected with:

```bash
cat "$HOME/.morro-termux-agent/supervisor.pid"
tail -n 100 "$HOME/.morro-termux-agent/logs/boot-supervisor.log"
```

Do not reactivate Commander as the default recovery path.

## 10. Validated acceptance evidence

The bridge has been physically validated on the tablet.

Validated flows include:

- ChatGPT -> GitHub -> Termux -> GitHub -> ChatGPT
- ChatGPT -> GitHub -> Termux -> Debian/PRoot -> GitHub -> ChatGPT
- agent crash -> supervisor automatically starts a new agent
- Android reboot -> Termux:Boot -> supervisor -> agent
- post-reboot Termux command execution
- post-reboot Debian command execution

Historical proof issues in this repository include:

- #15 — Native Agent V3/result formatter proof
- #23 — supervisor post-stop recovery proof
- #25 — post-reboot Termux persistence proof
- #26 — post-reboot Debian end-to-end proof
- #27 — legacy Commander autostart disabled

These are historical evidence only. Always query current live state before acting.

## 11. Canonical files

- `CHATGPT-START-HERE.md` — this contract
- `scripts/termux-native-agent.sh` — native job agent
- `scripts/termux-native-agentctl.sh` — lifecycle controller
- `scripts/termux-native-supervisor.sh` — recovery supervisor
- `scripts/termux-native-agent-heartbeat.test.sh` — heartbeat singleton regression proof
- `docs/NATIVE_AGENT.md` — architecture documentation
- `~/.termux/boot/20-morro-native-agent.sh` — tablet boot hook (local device)

## 12. Authority rule

Never rely on a hardcoded repository SHA from this document or an older conversation.

Before modifying code or assuming state:

```
fetch current main
verify current heartbeat
verify current job/result state
```

The live repository and live agent heartbeat are the source of truth.
