# helix-core-on-azure

Infrastructure as code for a production-shaped Perforce Helix Core estate —
commit, edge, proxy, broker, cross-region standby, P4 Code Review and P4 Search —
deployed through a gated pipeline, with monitoring that watches the things that
actually take Perforce down.

**This README is a methodology, not a setup guide.** Setup lives in
[docs/GETTING-STARTED.md](docs/GETTING-STARTED.md).

---

## 1. What actually takes Helix Core down

In rough order of how often it happens, not how dramatic it sounds.

**The journal volume fills.** p4d cannot write the journal, so it stops. This is
the outage nobody sees coming, because the metadata volume still looks healthy
and every generic monitoring dashboard is green.

**The metadata volume fills.** Worse than the journal case and far slower to
recover from, because recovery may mean a checkpoint restore rather than freeing
space and restarting.

**A checkpoint has been silently failing.** Costs nothing on the day it happens.
Costs everything on the day you need to restore.

**Nobody has ever tested a restore.** The first restore attempt happens during
the outage, under time pressure, by someone who has not done it before.

**The replica is further behind than anyone thinks.** The runbook claims an RPO.
Nothing measures it. The gap is discovered during failover.

**A lock-holding command stalls everyone.** One `p4 sync` against a huge path,
and the whole studio is blocked while every dashboard shows normal CPU.

**The licence expires.** Unglamorous. Has taken down more servers than hardware.

## 2. The design decisions that prevent each one

**Three separate volumes — `p4db`, `p4logs`, `p4depots`.**
Metadata, journal/logs, and archive files each get their own disk. A full
`p4logs` halts the server; if journal shares a volume with metadata, ordinary
depot growth can take the whole instance down. This one decision addresses the
first two failure modes above. See `provisioning/common/volumes.sh`.

**Checkpoint alerting on failure *and* overrun.**
Not just "did it run" but "did it finish inside its window" — a checkpoint
that is quietly taking three times as long is a capacity problem announcing
itself early. See `modules/observability`.

**Scheduled restore verification.**
A job restores the newest checkpoint into a scratch instance, verifies it, and
emits a metric. If that metric goes stale, an alert fires. Almost nobody builds
this. It is the difference between having backups and having recovery. See
`modules/backup`.

**Measured replica lag, not assumed.**
The standby runs journalcopy and the lag is a first-class metric with an alert
on it. Your RPO becomes a number you can show someone. See `modules/standby`.

**A broker in front.**
Controlled failover and honest read-only maintenance windows, rather than
"the server is down and nobody knows why." See `modules/broker`.

**Default-deny segmentation, no public IPs, managed identity everywhere.**
No Perforce host has a public IP in any environment. Nodes authenticate to Key
Vault and blob storage with system-assigned managed identities; the pipeline
authenticates to Azure with OIDC. There is no long-lived credential anywhere in
this repository or its state.

## 3. Assessing an existing estate

The same questions, in order, for someone else's Perforce environment:

1. Are metadata, journal and depots on separate volumes? What happens at 100%
   on each?
2. When did a checkpoint last succeed? What is the trend in its duration?
3. When was a restore last performed end to end, by whom, and how long did it
   take?
4. What is the measured replica lag right now, and what does the runbook claim
   the RPO is?
5. Who is paged when p4d stops, and on what signal?
6. What is the projected days-to-full on the depot volume?
7. When does the licence expire?

Questions 3 and 4 separate estates that have a DR plan from estates that have a
DR document.

## 4. What this deploys

| Module | Role |
|---|---|
| `network` | VNet, default-deny NSGs, tier segmentation |
| `storage` | Key Vault, offsite checkpoint blob container |
| `p4-node` | The VM/disk/identity primitive every role wraps |
| `commit-server` / `edge-server` / `standby` | Perforce servers, three-volume layout |
| `proxy` / `broker` | Cache and routing tiers |
| `swarm` / `p4search` | P4 Code Review, P4 Search |
| `backup` | Checkpoint offsite copy + restore verification |
| `observability` | Log Analytics, DCRs, the twelve alerts |

Environments: `dev` (one commit server), `stage` (commit + edge + proxy + Swarm),
`prod` (full topology + cross-region standby). Every VM defaults to the smallest
SKU that will run its role — this repo optimises for capability, not throughput.

A credit-free local option using the same provisioning scripts lives in
[`local/hyperv`](local/hyperv/README.md).

## 5. Platform constraints worth knowing

- **OS: Ubuntu 24.04 LTS** (or RHEL/Rocky 9). *Not* Ubuntu 26.04 — P4 Code
  Review 2026.3 supports Ubuntu 22.04/24.04 LTS, RHEL 8/9 and Rocky 8/9 only,
  and Swarm support is the binding constraint for the whole estate.
- **Swarm:** Apache 2.4 **prefork MPM only**, non-threaded PHP 8.2–8.5 (the P4
  PHP API is not thread-safe), Redis required, Linux only.
- **P4 Search:** fronts Elasticsearch; Perforce's own small-site floor is
  4 vCPU / 8 GB RAM *per component*. Off by default here, because that floor
  fights the minimum-footprint goal.
- **SDP** is installed by parameter (`install_sdp`), so a plain p4d can be stood
  up alongside for comparison.

Sources: Perforce documentation for
[P4 Code Review runtime dependencies](https://help.perforce.com/helix-core/helix-swarm/swarm/current/Content/Swarm/setup.dependencies.html)
and [P4 Search installation requirements](https://help.perforce.com/helix-core/integrations-plugins/p4search/current/Content/P4Search/prereqs-scenarios.html).

## 6. Working on Windows

Every script has a PowerShell counterpart; the bash versions exist because the
GitHub Actions runners are Linux.

| Task | PowerShell | bash / CI |
|---|---|---|
| Install pinned tooling | `.\scripts\setup-env.ps1` | `./scripts/setup-env.sh` |
| Pre-commit checks | `.\scripts\ci-checks.ps1` | `./scripts/ci-checks.sh` |
| Destroy an environment | `.\scripts\teardown.ps1 -Environment dev` | `./scripts/teardown.sh dev` |
| Build the local lab | `.\local\hyperv\New-P4Lab.ps1` | — (Hyper-V is Windows-only) |

The pairs run the same sequence against the same `dependencies.txt`. Keep them
in step when you change either.
