# Touristic Digital Platform — Bare Store + Disposable Worktrees

This runbook defines the tablet checkout model for the Touristic Digital Platform repository.

## Authority

GitHub live main is the source of truth. The tablet is compute capacity, not repository authority.

The legacy checkout at $HOME/touristic-digital-platform must not be used as a persistent writable baseline. It may remain temporarily for forensic reads while migration completes.

The canonical local Git object store is $HOME/repos/touristic-digital-platform.git.

It is bare and uses partial-clone filtering. Task work happens only in disposable worktrees under $HOME/worktrees.
## Lifecycle

Read-only discovery does not create a task branch.

After the Control Plane grants a task and lease, create a fresh detached worktree from the exact observed ref and SHA.

Commands:

    cd "$HOME/morro-termux-control"
    scripts/tdp-worktreectl.sh bootstrap
    scripts/tdp-worktreectl.sh refresh
    scripts/tdp-worktreectl.sh create MD-TASK-123 lease-abc refs/heads/main <40-char-main-sha>

The controller fails closed if the fetched ref does not resolve to the expected SHA.

The generated path includes task ID, lease ID, and the exact SHA prefix. An existing path is never reused.

A writer may create its task branch inside that fresh worktree only after claim and lease authority exists.
## Retirement and quarantine

When a task is merged, closed, or superseded, retire its worktree:

    scripts/tdp-worktreectl.sh retire "$HOME/worktrees/<task-lease-sha>"

A clean worktree is removed and pruned.

A dirty worktree is not deleted. The controller returns QUARANTINED, preserves the directory, and writes quarantine metadata under $HOME/worktrees/.morro-meta/quarantine.

A quarantined worktree must never be assigned to another writer.

Local bare-store branch refs are disposable cache. To remove stale local branch refs without touching GitHub:

    scripts/tdp-worktreectl.sh compact-local-refs
## Operational invariants

- Fetch live GitHub state before choosing a task.
- Do not infer current main from an old checkout.
- Do not create a branch for investigation.
- Do not reuse a worktree between writers or leases.
- Never delete a dirty worktree automatically.
- Never delete remote GitHub branches from this controller.
- A worktree path is not a state registry; task state belongs to the Control Plane.
- The controller serializes bare-store mutations with a fail-closed local lock.
- Exact SHA mismatch aborts before a worktree is created.
- Remote credentials stay in the existing authenticated Git and CLI stores.

## Health

Inspect the store and registered worktrees with:

    scripts/tdp-worktreectl.sh status

The expected steady state is one bare store, a small number of active task worktrees, and no reused or silently dirty worktrees.
