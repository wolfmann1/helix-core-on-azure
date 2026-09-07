# Runbook

Every procedure here should be executed at least once in `dev` or the Hyper-V
lab before it is needed. A runbook nobody has rehearsed is a document, not a
plan.

## 1. Checkpoint restore

**When:** metadata corruption, or the metadata volume filled and truncated.

1. Stop p4d. Confirm it is stopped — a second p4d touching the same P4ROOT
   during recovery makes things worse.
2. Identify the newest verified checkpoint. `modules/backup`'s verification job
   is the source of truth for "verified"; do not assume the newest file is good.
3. Recover metadata from the checkpoint, then replay journals recorded after it,
   in order.
4. Verify the archive against the recovered metadata before letting users in.
5. Start p4d, confirm with a read-only command, then open the broker.

**Record the wall-clock time.** That number is your real RTO, and it belongs in
the audit rather than an estimate.

## 2. Failover to standby

**When:** the primary region is unavailable, or during a scheduled drill.

1. Read current replication lag. Anything the standby has not received is lost
   — that is your actual RPO for this event.
2. Stop journalcopy/pull on the standby.
3. Promote the standby.
4. Repoint the broker's target at the promoted server.
5. Verify: one read, one write, one proxy-served sync.
6. Record RPO and RTO.

**Run this as a drill at least once**, capture the numbers, and put them in the
README. A measured failover is the single most credible artefact this repo can
produce.

## 3. Adding an edge server

1. `edge_count` +1 in the environment's tfvars.
2. PR — the plan workflow comments the diff for review.
3. Merge; approve the gated apply.
4. Seed the edge from a commit checkpoint.
5. Confirm the new node appears in the observability workspace before declaring
   it done.

## 4. Journal or metadata volume approaching full

**Alert fired at 20%, page at 10%.**

1. Rotate the journal and confirm the rotated file is offsite.
2. Prune expired structured logs — `p4logs` is usually recoverable this way.
3. If `p4db` is the pressure: this is not a cleanup problem, it is a capacity
   problem. Grow the disk.
4. Re-check the days-to-full projection afterwards. Freeing 5% buys days, not
   weeks.

## 5. Restore verification failed or went stale

Treat as a tier-1 issue even though nothing is currently down. A failed
verification means the recovery path in section 1 is unproven. Fix it before the
next checkpoint cycle.

## 6. Tearing down an on-demand environment

`./scripts/teardown.sh <env>`. Capture evidence first — alert screenshots, plan
output, failover timings, restore verification result. The environment is
disposable; the evidence is not.
