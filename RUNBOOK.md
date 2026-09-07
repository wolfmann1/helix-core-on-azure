# Runbook

Each procedure here should be run at least once in `dev` or the Hyper-V lab
before it is needed in production.

## 1. Checkpoint restore

**When:** metadata corruption, or the metadata volume filled and truncated.

1. Stop p4d and confirm it is stopped. A second p4d touching the same P4ROOT
   during recovery will make the situation worse.
2. Identify the most recent verified checkpoint. Use the verification job in
   `modules/backup` as the source of truth rather than assuming the newest file
   is usable.
3. Recover metadata from the checkpoint, then replay any journals recorded after
   it, in order.
4. Verify the archive against the recovered metadata before allowing users back
   in.
5. Start p4d, confirm with a read-only command, then reopen the broker.

Record the wall-clock time. That figure is the environment's actual RTO and
belongs in the audit output rather than an estimate.

## 2. Failover to standby

**When:** the primary region is unavailable, or during a scheduled drill.

1. Read the current replication lag. Anything the standby has not received is
   lost, and that figure is the actual RPO for this event.
2. Stop journalcopy and pull on the standby.
3. Promote the standby.
4. Repoint the broker at the promoted server.
5. Verify with one read, one write, and one proxy-served sync.
6. Record the resulting RPO and RTO.

Run this as a drill at least once and record the numbers in the README. A
measured failover is more useful evidence than any other artefact this
repository produces.

## 3. Adding an edge server

1. Increment `edge_count` in the environment's tfvars.
2. Open a pull request. The plan workflow posts the diff for review.
3. Merge, then approve the gated apply.
4. Seed the edge from a commit checkpoint.
5. Confirm the node appears in the observability workspace before considering
   the change complete.

## 4. Journal or metadata volume approaching full

Alert fires at 20% free, pages at 10%.

1. Rotate the journal and confirm the rotated file has been copied offsite.
2. Prune expired structured logs. `p4logs` pressure is usually recoverable this
   way.
3. If the pressure is on `p4db`, this is a capacity problem rather than a
   cleanup problem. Grow the disk.
4. Recheck the days-to-full projection afterwards. Freeing 5% typically buys
   days rather than weeks.

## 5. Restore verification failed or went stale

Treat this as urgent even though nothing is currently down. A failed
verification means the procedure in section 1 is untested against current data.
Resolve it before the next checkpoint cycle.

## 6. Tearing down an on-demand environment

Run `.\scripts\teardown.ps1 -Environment <env>` (or `./scripts/teardown.sh
<env>`).

Capture evidence first: alert screenshots, plan and apply output, failover
timings, and the most recent restore verification result. The environment can be
rebuilt from this repository at any time; the recorded evidence cannot.
