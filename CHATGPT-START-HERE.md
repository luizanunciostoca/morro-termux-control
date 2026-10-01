# CHATGPT START HERE — Persistent Termux Operator Contract

> Durable operating contract for ChatGPT sessions that need to use the Morro Digital Android/Termux environment.

## 1. Persistent capability exists

Canonical control repository:

`luizanunciostoca/morro-termux-control`

Repository visibility must remain **PRIVATE**.

There are two supported remote execution transports.

### Primary — direct Remote Desktop Commander

```text
ChatGPT
  -> Remote Desktop Commander MCP
  -> paired Remote Device on the tablet
  -> Termux shell / filesystem / processes
```

This path does **not** use GitHub Issues for command transport.

The persistent local pieces are:

```text
~/.termux/boot/10-morro-remote-commander.sh
  -> scripts/termux-remote-commander-supervisor.sh
  -> scripts/termux-remote-commanderctl.sh
  -> @wonderwhy-er/desktop-commander remote
```

### Fallback — Native Termux Agent V3 over GitHub Issues

```text
ChatGPT
  -> GitHub connector
  -> private GitHub Issue [TERMUX-JOB]
  -> Native Termux Agent V3
  -> target: Termux or Debian/PRoot
  -> stdout/stderr/result metadata posted to the issue
  -> issue closed
```

The fallback starts automatically after Android reboot:

```text
Android boot
  -> Termux:Boot
  -> ~/.termux/boot/20-morro-native-agent.sh
  -> scripts/termux-native-supervisor.sh
  -> scripts/termux-native-agent.sh daemon
```

Never conclude that the tablet is inaccessible merely because one transport is unavailable.

## 2. Transport selection

For ordinary shell/filesystem/process work:

1. Check Remote Desktop Commander device state first.
2. If the tablet is online there, use Commander directly.
3. If Commander is offline or unavailable, check the Native Agent heartbeat.
4. If the Native Agent is healthy, use the GitHub-Issues fallback.
5. Ask for manual tablet intervention only when both transports are unavailable or Android requires a physical/UI action.

Do not route ordinary direct work through GitHub when Commander is healthy.

Do not disable or remove the GitHub fallback until the direct path has passed the acceptance tests in this document.

## 3. Direct Commander health and operation

Healthy direct state means all of the following are true:

- the Remote Desktop Commander device is listed as online;
- `ping` succeeds;
- a read-only shell probe succeeds;
- filesystem reads under the Termux home succeed.

The direct device lifecycle is controlled locally by:

```bash
cd "$HOME/morro-termux-control"
bash scripts/termux-remote-commanderctl.sh status
bash scripts/termux-remote-commanderctl.sh restart
bash scripts/termux-remote-commanderctl.sh logs
```

Interactive first-time or re-authorization pairing is:

```bash
bash scripts/termux-remote-commanderctl.sh pair
```

The authenticated Remote Device session remains local to the tablet. Never commit device credentials or tokens to GitHub.

## 4. Native Agent heartbeat fallback

Before issuing a GitHub fallback job, enumerate all **open** issues whose title is exactly:

`[TERMUX-AGENT] status`

Invariant:

- there must be exactly one open exact-title heartbeat;
- never trust or hardcode an issue number;
- never trust a cached PID, timestamp, SHA, or device state;
- use the live singleton and its fresh `heartbeat_utc` as authority.

Healthy state resembles:

```text
MORRO_NATIVE_AGENT_V3

state: ONLINE
build: native-v3
protocol_version: 2
agent_instance_id: <stable for one daemon lifetime>
boot_id: <kernel boot id>
heartbeat_utc: <timestamp>
arch: aarch64
pid: <numeric shell pid>
poll_seconds: 30
transport: GitHub Issues
targets: termux,debian
```

If the heartbeat is stale, allow at least one 60-second supervisor cycle before declaring the fallback unhealthy.

## 5. Creating a Native Agent fallback job

Create a GitHub issue in the canonical private repository.

Title:

```text
[TERMUX-JOB] <short descriptive title>
```

Body must be raw JSON:

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

Rules:

- `version`: `2`
- `confirm`: exactly `EXECUTE`
- `id`: letters, numbers, dot, underscore or hyphen
- `target`: `termux` or `debian`
- `cwd`: working directory; `~` and `~/...` are supported
- `timeout_seconds`: 1 through 3600
- `command`: shell command/script

The agent accepts jobs only from the authorized repository owner.

## 6. Reading a Native Agent result

A completed fallback job is normally closed and contains a comment beginning:

```text
MORRO_AGENT_RESULT_V3
```

Inspect at minimum:

- `id`
- `target`
- `exit_code`
- `started_at`
- `ended_at`
- `duration_seconds`
- `request_sha256`
- `stdout`
- `stderr`

Do not infer success merely from issue closure. Success normally requires `exit_code: 0` plus expected output.

## 7. Target semantics

### Termux

Typical capabilities include:

- git / gh
- bash
- curl
- jq
- node/npm/pnpm when installed
- Python when installed
- Termux utilities
- proot-distro
- filesystem/process/network commands allowed by Android/Termux permissions

### Debian

Runs inside Debian GNU/Linux 13 (trixie), PRoot, ARM64/aarch64, home `/root`.

An effective uid of 0 inside PRoot is **not Android kernel root**.

## 8. Security and execution rules

Both transports operate under the tablet user's effective permissions and are intentionally auditable.

Never place passwords, PATs, registration tokens, API secrets, private keys, or other long-lived secrets in GitHub issue bodies, source files, logs intended for publication, or chat text.

Prefer already-authenticated local CLIs and local credential stores.

The Native Agent fallback remains fail-closed with repository/owner checks, request schema validation, explicit confirmation, bounded timeouts, stdout/stderr capture, request hashing, replay protection, supervisor recovery, and boot persistence.

The Commander path must keep its saved device authorization local to the tablet.

## 9. Operational behavior for future chats

When the user asks to inspect, build, test, modify, run, deploy, diagnose, or operate something available through the tablet:

1. Recapture the current `main` of this repository.
2. Check Remote Desktop Commander device state.
3. If online, use Commander directly and gather concrete evidence.
4. If offline, check the exact-title Native Agent heartbeat singleton.
5. If the fallback is healthy, use it.
6. Iterate until the requested task is complete.
7. Report the transport used and concrete result evidence.

Do **not** send the user manual Termux commands first while either remote transport is healthy.

Do **not** say "Termux has no access" merely because a ChatGPT-side connector/tool call is blocked. Distinguish at least:

- `DIRECT_COMMANDER_OFFLINE`
- `NATIVE_AGENT_HEARTBEAT_STALE`
- `GITHUB_JOB_DISPATCH_BLOCKED_BY_CLIENT`
- `GITHUB_CONNECTOR_UNAVAILABLE`
- `TABLET_UNREACHABLE_BOTH_TRANSPORTS`

## 10. Recovery

### Direct Commander offline

First check the connected device list. If the tablet is offline and the Native Agent fallback is healthy, use the fallback to inspect/restart Commander.

Local recovery commands are:

```bash
cd "$HOME/morro-termux-control"
bash scripts/termux-remote-commanderctl.sh status
bash scripts/termux-remote-commanderctl.sh restart
```

If pairing is required:

```bash
bash scripts/termux-remote-commanderctl.sh pair
```

### Native Agent heartbeat stale

1. allow at least one 60-second supervisor cycle;
2. re-enumerate exact-title open heartbeat issues and verify singleton + freshness;
3. if still stale, use Commander when available;
4. otherwise local break-glass recovery is:

```bash
cd "$HOME/morro-termux-control"
bash scripts/termux-native-agentctl.sh status
bash scripts/termux-native-agentctl.sh recover
```

## 11. Acceptance evidence

### Native Agent fallback — historically validated

Validated flows include:

- ChatGPT -> GitHub -> Termux -> GitHub -> ChatGPT
- ChatGPT -> GitHub -> Termux -> Debian/PRoot -> GitHub -> ChatGPT
- agent crash -> supervisor recovery
- Android reboot -> Termux:Boot -> supervisor -> agent
- post-reboot Termux execution
- post-reboot Debian execution

Historical proof issues include #15, #23, #25, #26 and #27. They are historical evidence only.

### Direct Commander — acceptance required after bootstrap

The direct path becomes the preferred operational transport only after all of these pass:

1. tablet appears online in Remote Desktop Commander;
2. ChatGPT `ping` succeeds;
3. ChatGPT executes a read-only shell probe;
4. ChatGPT creates and deletes a temporary file under the Termux home;
5. a controlled Remote Device restart reconnects without re-pairing;
6. Android reboot reconnects without manual command entry.

Until these are proven, keep the Native Agent fallback enabled.

## 12. Canonical files

- `CHATGPT-START-HERE.md` — this contract
- `docs/DIRECT_ACCESS.md` — direct Commander runbook
- `scripts/termux-remote-commanderctl.sh` — direct device lifecycle controller
- `scripts/termux-remote-commander-supervisor.sh` — direct device recovery supervisor
- `scripts/install-direct-commander.sh` — Termux:Boot installer
- `scripts/direct-commander-bootstrap.test.sh` — direct bootstrap regression proof
- `scripts/termux-native-agent.sh` — GitHub fallback job agent
- `scripts/termux-native-agentctl.sh` — fallback lifecycle controller
- `scripts/termux-native-supervisor.sh` — fallback recovery supervisor
- `scripts/termux-native-agent-heartbeat.test.sh` — fallback lifecycle/singleton regression proof
- `docs/NATIVE_AGENT.md` — fallback architecture documentation
- `~/.termux/boot/10-morro-remote-commander.sh` — direct tablet boot hook after installation
- `~/.termux/boot/20-morro-native-agent.sh` — fallback tablet boot hook

## 13. Authority rule

Never rely on a hardcoded repository SHA, issue number, PID, device state, or timestamp from this document or an older conversation.

Before modifying code or assuming state:

```text
fetch current main
check direct Commander device state
check live heartbeat fallback
check current job/result state when using GitHub fallback
```

The live repository plus the live state of both transports are the source of truth.
