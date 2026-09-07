# Architecture

## Topology

```
                     ┌──────────────┐
   developers ──────▶│   p4broker   │  routing, maintenance windows, failover
                     └──────┬───────┘
                            │
        ┌───────────────────┼────────────────────┐
        │                   │                    │
   ┌────▼────┐        ┌─────▼─────┐        ┌─────▼─────┐
   │  proxy  │        │   edge    │        │  commit   │◀── authoritative
   │ (cache) │        │ (own db)  │        │  p4db     │    metadata + archive
   └─────────┘        └───────────┘        │  p4logs   │
                                           │  p4depots │
                                           └─────┬─────┘
                       ┌─────────────────────────┤
                  ┌────▼────┐              ┌─────▼──────┐
                  │  swarm  │              │  standby   │  journalcopy,
                  │ p4search│              │ (region 2) │  measured lag
                  └─────────┘              └────────────┘
```

## The decisions, and why

### Three volumes, not one
`p4db` (metadata), `p4logs` (journal + structured logs), `p4depots` (archive).

Stock SDP names these `/hxmetadata`, `/hxlogs`, `/hxdepots`. This repo mounts
`p4db`/`p4logs`/`p4depots` and symlinks the SDP paths onto them, so SDP tooling
runs unmodified while the volume names say what they hold.

Rationale: a full `p4logs` stops the server outright, because the journal cannot
be written. If the journal shares a volume with metadata, routine depot or log
growth becomes an availability incident. Separating them means each failure is
bounded and each has its own alert.

Disk caching differs per volume — `ReadOnly` host caching on `p4db`, `None` on
`p4logs` and `p4depots`. Write-heavy sequential journal I/O gains nothing from
host cache and can be hurt by it.

### An edge has its own metadata
That is what an edge *is*. The `edge-server` module therefore attaches its own
`p4db`; sharing commit's would defeat the purpose. A proxy, by contrast, caches
file content only and gets one volume.

### Terraform creates infrastructure; `provisioning/` creates configuration
Nothing under `provisioning/` knows what a resource group is. That boundary is
not tidiness — it is what makes `local/hyperv` possible. The same
`provision.sh --role commit --install-sdp true` runs on an Azure VM via
cloud-init and on a Hyper-V guest over SSH, and produces the same server.

### Role modules are thin wrappers over `p4-node`
`p4-node` owns VM, disks, managed identity and provisioning wiring.
`commit-server`, `edge-server`, `proxy`, `broker`, `standby`, `swarm` and
`p4search` each supply that primitive with the role's opinionated defaults —
principally which data disks exist. Adding a role is a twenty-line module.

### No credentials, anywhere
Nodes use system-assigned managed identities to read Key Vault and write
checkpoints to blob. The pipeline uses OIDC federated credentials rather than a
service principal secret. The state account has `shared_access_key_enabled =
false`, forcing Entra ID auth. There is no long-lived secret in the repo, in
state, or in cloud-init.

### One state file per environment
Not one global state. A `dev` mistake cannot corrupt `prod` state, and plan
times stay short.

## Deliberate non-goals

Stated out loud, because a defended scoping decision reads as judgement while a
silent omission reads as a gap.

- **No Kubernetes.** p4d is a stateful service with hard storage-latency
  requirements. Containerising the commit server is not the industry norm and
  claiming otherwise would be posturing. The proxy tier is the only part of this
  estate where containers would genuinely help.
- **No multi-cloud.** Azure plus a local Hyper-V option. Depth over breadth.
- **No Windows Perforce hosts.** Linux SDP only. Swarm does not support Windows
  at all, and adding a second OS family doubles the provisioning surface while
  proving nothing new.
- **P4 Search off by default.** Its floor is 4 vCPU / 8 GB per component, which
  is larger than the entire dev environment.
