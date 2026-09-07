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

## Decisions

### Three volumes rather than one

`p4db` holds metadata, `p4logs` holds the journal and structured logs, and
`p4depots` holds archive files.

SDP expects these at `/hxmetadata`, `/hxlogs` and `/hxdepots`. This repository
mounts the `p4*` names and symlinks the SDP paths onto them, so SDP tooling runs
unmodified while the mount points describe their contents.

The reason for the split: a full `p4logs` stops p4d, because the journal cannot
be written. If the journal shares a volume with metadata, ordinary depot or log
growth becomes an availability incident. Separate volumes keep each failure
contained and allow separate alert thresholds.

Host caching differs per volume. `p4db` uses ReadOnly caching; `p4logs` and
`p4depots` use none. Sequential journal writes gain nothing from host cache and
can be slowed by it.

### An edge server has its own metadata

That is the defining characteristic of an edge server, so the `edge-server`
module attaches its own `p4db` volume rather than sharing the commit server's. A
proxy caches file content only and gets a single volume.

### Terraform creates infrastructure, `provisioning/` configures it

Nothing under `provisioning/` references Azure concepts. That separation is what
allows the Hyper-V path to work: the same
`provision.sh --role commit --install-sdp true` runs on an Azure VM through
cloud-init and on a Hyper-V guest over SSH, producing the same server.

### Role modules wrap a shared primitive

`p4-node` owns the VM, disks, managed identity and provisioning wiring. The
`commit-server`, `edge-server`, `proxy`, `broker`, `standby`, `swarm` and
`p4search` modules supply it with role-specific defaults, mainly which data
disks exist. Adding a new role takes about twenty lines.

### No stored credentials

Nodes use system-assigned managed identities to read Key Vault and write
checkpoints to blob storage. The pipeline uses OIDC federated credentials rather
than a service principal secret. The state storage account sets
`shared_access_key_enabled = false`, requiring Entra ID authentication. Nothing
long-lived is written to the repository, to state, or to cloud-init.

### One state file per environment

A mistake in `dev` cannot corrupt `prod` state, and plan times stay short.

## Scope exclusions

These are deliberate, and documented so they are not mistaken for oversights.

- **Kubernetes.** p4d is stateful with strict storage latency requirements, and
  containerising the commit server is not common practice. The proxy tier is the
  only part of this estate where containers would offer a clear benefit.
- **Multi-cloud.** Azure only, plus a local Hyper-V option.
- **Windows Perforce hosts.** Linux SDP only. Swarm does not support Windows,
  and a second OS family would double the provisioning surface without
  demonstrating anything new.
- **P4 Search enabled by default.** Its requirement of 4 vCPU and 8 GB RAM per
  component exceeds the size of the entire dev environment.
