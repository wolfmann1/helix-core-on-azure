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

### Volume layout

| Volume | Holds | Default size | Notes |
|---|---|---|---|
| `p4db` | metadata, `db.*` files | 2 GiB | ReadOnly host caching |
| `p4db2` | second metadata volume | 2 GiB | Omitted when `split_metadata = false` |
| `p4logs` | journal and structured logs | 2 GiB | No host caching |
| `p4depots` | versioned archive files | 5 GiB | No host caching |
| `p4` | SDP root | 1 GiB | Only when `separate_sdp_volumes = true`, otherwise on `p4depots` |
| `p4ckps` | checkpoints | 1 GiB | Same condition as `p4` |
| `p4serverlocks` | `server.locks` | 1024 MiB tmpfs | RAM, not a disk |

SDP expects these under the `hx*` names. `provisioning/common/volumes.sh` mounts
the `p4*` names and symlinks `/hxmetadata`, `/hxmetadata1`, `/hxmetadata2`,
`/hxlogs`, `/hxdepots`, `/hxcheckpoints` and `/hxserverlocks` onto them, so SDP
tooling runs unmodified and the mount points describe their contents.

The defaults are sized for an environment that is built up and torn down
repeatedly rather than one holding real depot content. Override any of them
through `disk_sizes_gb`.

**Why the volumes are split.** A full `p4logs` stops p4d, because the journal
cannot be written. If the journal shares a volume with metadata, ordinary depot
or log growth becomes an availability incident. Separate volumes keep each
failure contained and allow separate alert thresholds.

**Why metadata is split across two volumes by default.** SDP supports placing
`db.*` files across two metadata volumes, which separates the I/O of the largest
tables from the rest. At lab sizes this makes no measurable difference, but it
means the topology and the provisioning path match a real deployment. Set
`split_metadata = false` for a single metadata volume.

**Server locks in RAM.** SDP recommends placing the `server.locks` directory on
tmpfs. It is created as an fstab tmpfs entry rather than a managed disk. Set
`serverlocks_tmpfs_mb = 0` to skip it.

### Disk tier and Azure size floors

`disk_tier` selects the managed disk type for every data disk on a node:

| `disk_tier` | Azure type | Smallest disk | Host caching |
|---|---|---|---|
| `standard` (default) | `StandardSSD_LRS` | 4 GiB | Supported |
| `premium` | `Premium_LRS` | 4 GiB | Supported |
| `premium_v2` | `PremiumV2_LRS` | 1 GiB, 1 GiB increments | Not supported |
| `hdd` | `Standard_LRS` | 32 GiB | Supported |

Azure will not allocate a disk below its type's smallest tier. The 2 GiB
defaults therefore become 4 GiB on `standard` and `premium`, and 32 GiB on
`hdd`. `modules/p4-node` rounds requested sizes up to the floor rather than
failing, so a rebuild does not error on a size Azure will not allocate. Only
`premium_v2` allocates 2 GiB exactly, and it requires a zonal VM in most regions
and does not support host caching — set `zone` when using it.

Host caching differs per volume where the type supports it: `p4db` and `p4db2`
use ReadOnly, everything else uses none. Sequential journal writes gain nothing
from host cache and can be slowed by it.

### Disks are formatted by the guest, mapped by LUN

Terraform attaches raw disks; it does not format them. `volumes.sh` creates the
filesystem, applies the label, and mounts it.

Device names such as `/dev/sdb` are not stable across reboots, so the script
does not use them. Terraform passes `--disk-map "p4db=0,p4db2=1,p4logs=2,
p4depots=3"`, built from the same map used to attach the disks, and the guest
resolves each LUN through a by-path symlink: `/dev/disk/azure/scsi1/lunN` where
the Azure agent is present, and the generic SCSI by-path form otherwise, which
is what the Hyper-V path uses.

A disk with no label is formatted. A disk already carrying the expected label is
left alone, so re-running provisioning is safe. A disk carrying a *different*
label is refused rather than reformatted, since that is more likely a mistake
than something to overwrite.

Whole-disk filesystems, no partition table. Each disk serves one volume, so
partitioning adds nothing and makes growing the disk harder.

### Provisioning scripts are embedded in cloud-init

`modules/p4-node` reads the `provisioning/` tree and writes it into
`custom_data` as base64, and cloud-init unpacks it to `/opt/p4-provisioning`
before running `provision.sh`.

Fetching from the checkpoint storage account would be the better design, but it
does not work yet: that account has public network access disabled and there
are no private endpoints, so nothing inside the VNet can reach it. Embedding
needs no network and no credentials, and produces a node identical to the
Hyper-V path.

`custom_data` is capped at 64 KB base64. The tree is around 19 KB, and a
`precondition` on the VM fails the plan if it grows past the limit rather than
letting Azure reject the deployment with a less obvious error. Once private
endpoints exist, this should become a blob fetch.

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

### Node names carry the region

Nodes are named `p4-<env>-<region code>-<role>-<nn>`, for example
`p4-dev-cae-commit-01`. The codes are in a map in each environment's `locals`.

The reason is managed identities. A VM's system-assigned identity is a service
principal in Entra ID stamped with the VM's region, and it outlives the VM.
Recreating a VM with the same resource ID -- same subscription, resource group
and name -- in a different region fails with
`AlreadyExistServicePrincipalInDifferentRegion`, and that principal cannot be
deleted directly because the resource provider owns it rather than the
directory administrator. Including the region keeps resource IDs distinct per
region, so a region change never collides.

It also makes the prod topology readable: the commit server is
`p4-prod-cae-commit-01` and its standby is `p4-prod-wus2-standby-01`, so which
side of a failover you are looking at is visible in the name.

### Key Vault uses RBAC, and access is granted by an explicit flag

The vault sets `rbac_authorization_enabled = true`, so node identities are
granted the **Key Vault Secrets User** role rather than an access policy entry.
That role is read-only on secret values, which is all a node needs.

Whether a node gets that grant is controlled by `grant_key_vault_access`, a
bool, rather than by testing whether `key_vault_id` is empty. The id comes from
the Key Vault resource and is unknown until apply, and `count` cannot depend on
a value Terraform does not know while building the graph -- the plan fails with
"The count value depends on resource attributes that cannot be determined until
apply". Anything that decides whether a resource exists has to be knowable at
plan time.

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
