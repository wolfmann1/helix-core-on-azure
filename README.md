# helix-core-on-azure

Terraform configuration for a Perforce Helix Core estate on Azure: commit
server, edge servers, proxies, broker, cross-region standby, P4 Code Review and
P4 Search. Deployed through a GitHub Actions pipeline with an approval gate, and
monitored with alerts specific to Perforce rather than generic VM metrics.

Setup is in [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md). Every failure
encountered building this, with causes and commands, is in
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
This file covers the failure modes the design addresses and the reasoning behind
each choice.

---

## 1. Common Helix Core failure modes

Ordered by how often they occur.

**The journal volume fills.** p4d cannot write the journal and stops. Generic
infrastructure monitoring usually misses this, because the metadata volume and
the OS disk both still look healthy.

**The metadata volume fills.** Recovery is slower than the journal case, because
it may require a checkpoint restore rather than freeing space and restarting.

**Checkpoints have been failing silently.** No impact until a restore is needed,
at which point the most recent usable checkpoint may be weeks old.

**No one has tested a restore.** The first attempt happens during an outage,
under time pressure.

**Replica lag is larger than assumed.** The runbook states an RPO, but nothing
measures it. The gap becomes visible during failover.

**A lock-holding command blocks other users.** A single large sync can stall a
studio while CPU and memory graphs stay flat.

**The licence expires.** Common, and entirely preventable with a countdown
alert.

## 2. Design decisions

**Separate volumes for metadata, journal and archive.**
`p4db` and `p4db2` hold metadata, `p4logs` holds the journal and structured
logs, `p4depots` holds archive files, and `server.locks` sits on a tmpfs. A full
`p4logs` stops the server. If the journal shares a volume with metadata, depot
or log growth can cause an outage on the metadata volume. Separating them bounds
each failure and gives each its own alert threshold. Sizes and disk tier are
configurable per environment; see ARCHITECTURE.md for the layout table and the
Azure size floors. Implemented in `provisioning/common/volumes.sh`.

**Checkpoint alerts on both failure and duration.**
A checkpoint that still succeeds but now takes three times as long is an early
capacity signal. See `modules/observability`.

**Scheduled restore verification.**
A job restores the most recent checkpoint into a scratch instance, verifies it,
and emits a metric. An alert fires if that metric goes stale. See
`modules/backup`.

**Replica lag as a measured metric.**
The standby runs journalcopy and its lag is collected and alerted on, so the RPO
is a number rather than an estimate. See `modules/standby`.

**A broker in front of the estate.**
Supports controlled failover and read-only maintenance windows, and gives users
a clear message during either. See `modules/broker`.

**Default-deny networking, no public IPs, managed identity throughout.**
No Perforce host has a public IP in any environment. Nodes authenticate to Key
Vault and blob storage using system-assigned managed identities. The pipeline
authenticates to Azure with OIDC federated credentials. No long-lived credential
is stored in the repository, in Terraform state, or in cloud-init.

## 3. Assessing an existing estate

The same questions applied to someone else's environment:

1. Are metadata, journal and depots on separate volumes? What happens when each
   reaches 100%?
2. When did a checkpoint last succeed, and how has its duration trended?
3. When was a restore last performed end to end, by whom, and how long did it
   take?
4. What is the measured replica lag now, and what RPO does the runbook state?
5. Who is notified when p4d stops, and on what signal?
6. What is the projected days-to-full on the depot volume?
7. When does the licence expire?

Questions 3 and 4 are usually where documented recovery plans and tested
recovery plans diverge.

## 4. What this deploys

| Module | Role |
|---|---|
| `network` | VNet, default-deny NSGs, tier segmentation |
| `storage` | Key Vault, offsite checkpoint blob container |
| `p4-node` | VM, disk and identity primitive used by every role |
| `commit-server` / `edge-server` / `standby` | Perforce servers with the three-volume layout |
| `proxy` / `broker` | Cache and routing tiers |
| `swarm` / `p4search` | P4 Code Review, P4 Search |
| `backup` | Checkpoint offsite copy and restore verification |
| `observability` | Log Analytics, data collection rules, twelve alerts |

Environments: `dev` (commit server only), `stage` (commit, edge, proxy, Swarm),
`prod` (full topology plus cross-region standby). Every VM defaults to the
smallest SKU that runs its role, since the goal is to exercise the architecture
rather than serve production load.

A local Hyper-V option using the same provisioning scripts is documented in
[`local/hyperv`](local/hyperv/README.md).

## 5. Platform constraints

- **OS: Ubuntu 24.04 LTS**, or RHEL/Rocky 9. Not Ubuntu 26.04. P4 Code Review
  2026.3 supports Ubuntu 22.04 and 24.04 LTS, RHEL 8 and 9, and Rocky Linux 8
  and 9. Swarm has the narrowest OS support of any component here, so it sets
  the choice for the whole estate. `modules/p4-node` validates this at plan
  time.
- **Swarm:** Apache 2.4 with the prefork MPM only (worker and event are not
  supported), non-threaded PHP 8.2–8.5 because the P4 PHP API is not
  thread-safe, Redis required, Linux only.
- **P4 Search:** runs against Elasticsearch. Perforce's stated small-site
  requirement is 4 vCPU and 8 GB RAM per component, which is larger than the
  whole dev environment, so it is disabled by default and enabled explicitly
  per environment.
- **VM sizes: B-series v2.** B v1 (`Standard_B1s`, `Standard_B2s`) is announced
  for retirement on 15 November 2028, at which point VMs on those sizes are
  deallocated. Every role here uses `Standard_B2ats_v2`, which is AMD x64 and
  permitted by the lab guardrails. `Standard_B2pts_v2` is also permitted but is
  ARM64; using it would mean verifying Perforce and Swarm packaging for arm64
  first.
- **x86_64 only.** Perforce's apt repository publishes `binary-amd64` and
  `binary-i386` for Ubuntu, and no `binary-arm64`. p4d cannot be installed from
  the vendor repository on an Ampere VM, so every `Standard_B*p*` size is
  unusable regardless of policy or availability.
- **Allocation failure is not the same as SKU unavailability.**
  `SkuNotAvailable ... NotAvailableForSubscription` means the subscription is
  never offered that size there, and `az vm list-skus` shows it in advance.
  `AllocationFailed` means the datacenter has no free capacity for that size at
  that moment; it is transient and does not appear in `list-skus`, which reports
  subscription restrictions rather than live capacity. The remedies differ:
  change region or subscription for the first, retry or change size for the
  second.
- **SKU capacity is separate from SKU policy, and from architecture.** A size
  permitted by the guardrails can still be refused with `SkuNotAvailable`, which
  varies by region, zone and subscription type. On this subscription every x86
  B-series size is `NotAvailableForSubscription` in canadacentral, while the
  ARM sizes are available and unusable for the reason above. Check with
  `az vm list-skus --location <region> --size Standard_B --all -o table` before
  choosing; `vm_size` is an environment variable so switching is one line.
- **Alerts against custom tables need ingestion first.** Azure validates a
  scheduled query rule's KQL at creation and rejects a query against a table
  that does not exist. The seven alerts reading `*_CL` tables are held back by
  `custom_log_tables_ready`, which stays false until a data collection rule and
  an agent-side collector exist. The five alerts against built-in tables
  (InsightsMetrics, Syslog, Heartbeat) deploy regardless.
- **Lab subscription policy.** If the `az104-lab` guardrails are deployed on the
  target subscription, they deny any VM SKU outside `Standard_B2pts_v2`,
  `Standard_B2ats_v2`, `Standard_B1s` and `Standard_B2s`, and any region outside
  `canadacentral` and `canadaeast`. Every role here stays inside that list except
  P4 Search, which needs a larger SKU than the policy allows; enabling it means
  widening `allowedVmSkus` and redeploying the guardrails.
- **SDP** is installed via the `install_sdp` parameter, so a plain p4d can be
  deployed alongside for comparison.

## 6. Reference documentation

- [Getting Started with P4](https://help.perforce.com/helix-core/quickstart/current/Content/quickstart/Home-quickstart.html)
- [P4 Server Administration Guide (2026.1)](https://help.perforce.com/helix-core/server-apps/p4sag/current/Content/P4SAG/Home-p4sag.html)
- [P4 Server Deployment Package (SDP) Guide, UNIX/Linux](https://swarm.workshop.perforce.com/view/guest/perforce_software/sdp/main/doc/SDP_Guide.Unix.html) — volume layout, `mkdirs.sh`, checkpoint and journal scripts
- [P4 Code Review documentation (2026.3)](https://help.perforce.com/helix-core/helix-swarm/swarm/current/Content/Swarm/home-swarm.html) (formerly Helix Swarm), and its [runtime dependencies](https://help.perforce.com/helix-core/helix-swarm/swarm/current/Content/Swarm/setup.dependencies.html)
- [P4 Search documentation (2026.4)](https://help.perforce.com/helix-core/integrations-plugins/p4search/current/Content/P4Search/Home-p4search.html), and its [installation requirements](https://help.perforce.com/helix-core/integrations-plugins/p4search/current/Content/P4Search/prereqs-scenarios.html)
- [Azure managed disk types and sizes](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types) — the 4 GiB floor on Premium SSD v1 and Standard SSD

## 7. Working on Windows

Each script has a PowerShell version. The bash versions exist because the GitHub
Actions runners are Linux.

| Task | PowerShell | bash / CI |
|---|---|---|
| Install pinned tooling | `.\scripts\setup-env.ps1` | `./scripts/setup-env.sh` |
| Pre-commit checks | `.\scripts\ci-checks.ps1` | `./scripts/ci-checks.sh` |
| Destroy an environment | `.\scripts\teardown.ps1 -Environment dev` | `./scripts/teardown.sh dev` |
| Build the local lab | `.\local\hyperv\New-P4Lab.ps1` | Hyper-V is Windows only |

Both versions run the same checks against the same `dependencies.txt`. Update
them together.
