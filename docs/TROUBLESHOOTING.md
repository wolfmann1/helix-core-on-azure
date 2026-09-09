# Troubleshooting

Every failure hit while building this repository, with the error text, what
actually caused it, and the commands that fix it. Search by the error string.

Values in the examples come from the dev environment: subscription
`6443b9b0-bdc8-4987-b940-7aaea0b54983`, resource group `p4-dev-rg`, node
`p4-dev-cae-commit-01`. Substitute your own.

---

## Quick reference

| Symptom | Section |
|---|---|
| `terraform fmt exited 2` or `3` | [Terraform](#terraform) |
| `Plugin "azurerm" not found` | [Linters](#linters) |
| `Failed to resolve table or column expression named 'P4*_CL'` | [Azure Monitor](#azure-monitor) |
| `The "count" value depends on resource attributes` | [Terraform](#terraform) |
| `Key based authentication is not permitted` | [Storage](#storage) |
| `403` on the state container | [Storage](#storage) |
| `Instance cannot be destroyed` | [State](#state-and-lifecycle) |
| `Root object was present, but now absent` | [Region changes](#region-changes) |
| `the Resource Group still contains Resources` | [State](#state-and-lifecycle) |
| `AlreadyExistServicePrincipalInDifferentRegion` | [Region changes](#region-changes) |
| `SkuNotAvailable` / `AllocationFailed` | [VM sizing](#vm-sizing) |
| `a resource with the ID ... already exists` | [State](#state-and-lifecycle) |
| `was unexpected at this time` from `az` | [Windows](#windows) |
| `NativeCommandError` from `az` | [Windows](#windows) |
| PowerShell printing its own source | [Windows](#windows) |
| `Application Control policy has blocked this file` | [Windows](#windows) |

---

## Terraform

### `terraform fmt exited 2` vs `exited 3`

Different problems. **2 is a parse error**, 3 means the files parse but are not
canonically formatted.

`fmt` parses before it formats, so a syntax error surfaces there rather than at
`validate`, which is confusing the first time.

```powershell
.\scripts\ci-checks.ps1 -Fix     # rewrites formatting (fixes exit 3)
```

Exit 3 no longer stops the local run; exit 2 does. CI treats both as fatal.

### `Argument definition required` / `Invalid single-argument block definition`

```
on bootstrap\main.tf line 15, in provider "azurerm":
15: provider "azurerm" { features {} }
A single-line block definition can contain only a single argument.
```

A one-line HCL block may contain one *argument*. `features {}` is a nested
*block*, so it must go on its own line:

```hcl
provider "azurerm" {
  features {}
}
```

`delete_retention_policy { days = 30 }` is legal by the same rule -- one
argument -- but expanding it is more consistent.

### `The "count" value depends on resource attributes that cannot be determined until apply`

```hcl
# fails: key_vault_id comes from the Key Vault, unknown at plan time
count = var.key_vault_id == "" ? 0 : 1
```

`count` decides how many instances exist, and Terraform must know that while
building the graph. Gate on something knowable at plan time:

```hcl
count = var.grant_key_vault_access ? 1 : 0
```

The same applies to `for_each` keys.

---

## Linters

### `Failed to initialize plugins; Plugin "azurerm" not found`

tflint downloads the plugins named in `.tflint.hcl` on demand.

```powershell
tflint --init --config="$PWD\.tflint.hcl"
```

`ci-checks` and the plan workflow now do this automatically.

### A `tflint-ignore` comment is being ignored

It only applies when it is on the line **immediately** above the resource. Any
comment in between voids it silently -- the rule still fires and nothing reports
that the annotation was skipped.

```hcl
# Explanation goes above the annotation, not below it.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_account" "checkpoints" {
```

Same idea for `# checkov:skip=CKV_ID:reason`, which goes *inside* the resource
block.

---

## Azure Monitor

### `Failed to resolve table or column expression named 'P4Commands_CL'`

```
BadRequest: 'where' operator: Failed to resolve table or column expression
named 'P4Commands_CL'. A semantic error occurred.
```

Azure validates a scheduled query rule's KQL when the rule is created. Custom
tables (`_CL` suffix) do not exist until something ingests into them, so the
rule cannot be created first.

Alerts reading custom tables are gated:

```hcl
custom_log_tables_ready = false   # default
```

Five alerts against built-in tables (`InsightsMetrics`, `Syslog`, `Heartbeat`)
deploy regardless. Set it true once a data collection rule and a collector
exist.

There is a `skip_query_validation` argument that would force all of them
through. Do not use it. An alert that cannot resolve its table looks like
coverage on the dashboard and can never fire.

---

## Storage

### `Key based authentication is not permitted on this storage account`

```
waiting for the Data Plane for Storage Account ... to become available:
unexpected status 403 ... KeyBasedAuthenticationNotPermitted
```

After creating a storage account the provider polls the Blob service to confirm
it is up, using key-based auth by default. With
`shared_access_key_enabled = false` that poll is rejected -- and the account
already exists by then, so the apply fails on a resource that was created.

```hcl
provider "azurerm" {
  storage_use_azuread = true
  features {}
}
```

Set in `bootstrap` and every environment root.

### `403` creating a container, or on `terraform init` against the backend

Creating a container is a **data-plane** call. Control-plane roles, Owner
included, do not grant data-plane access. The caller needs a data-plane role:

```powershell
az role assignment create `
  --role "Storage Blob Data Contributor" `
  --assignee <object id> `
  --scope /subscriptions/<sub>/resourceGroups/p4-tfstate-rg/providers/Microsoft.Storage/storageAccounts/<name>
```

`bootstrap` and `modules/storage` assign this automatically to whoever applies
them, then wait 60 seconds (`time_sleep.rbac_propagation`) before the first
data-plane call, because RBAC is eventually consistent. A container create
immediately after the assignment still returns 403.

### Key Vault name unusable after a teardown

With `purge_protection_enabled = true`, a deleted vault cannot be purged early,
so its name stays reserved for the full soft-delete window (7 days here) and a
rebuild that generates the same name fails. Azure does not allow purge
protection to be turned off once a vault has it.

`key_vault_purge_protection` defaults to false. prod sets it true.

---

## State and lifecycle

### `Instance cannot be destroyed ... lifecycle.prevent_destroy`

Usually means the resource is **tainted**. Terraform taints a resource whose
create failed partway, and a tainted resource is always planned as
destroy-and-recreate, which `prevent_destroy` refuses.

```powershell
terraform untaint azurerm_storage_account.state
terraform plan     # should now say "update in-place", not "destroy and then create"
terraform apply
```

Do not remove `prevent_destroy` to get past it. On the state account it is
stopping a destroy-and-recreate of the state for every environment.

### `a resource with the ID ... already exists`

The resource exists in Azure but not in state -- an apply created it and then
failed before recording it. Check whether it is usable before deciding:

```powershell
az vm show -g p4-dev-rg -n p4-dev-cae-commit-01 `
  --query "{state:provisioningState, size:hardwareProfile.vmSize}" -o json
```

**`provisioningState: Succeeded`** -- adopt it:

```powershell
terraform -chdir=envs/dev import 'module.commit.module.node.azurerm_linux_virtual_machine.this' `
  "/subscriptions/6443b9b0-bdc8-4987-b940-7aaea0b54983/resourceGroups/p4-dev-rg/providers/Microsoft.Compute/virtualMachines/p4-dev-cae-commit-01"
```

**`provisioningState: Failed`** -- delete and re-apply:

```powershell
az vm delete -g p4-dev-rg -n p4-dev-cae-commit-01 --yes
```

> **Caveat.** `az vm delete` removes only the VM and leaves its OS disk
> orphaned. Do **not** clean up by listing unattached disks and deleting them
> all: the four data disks (`-p4db`, `-p4db2`, `-p4logs`, `-p4depots`) are
> unattached whenever the VM is gone and are managed by Terraform. Filter to the
> OS disk:
>
> ```powershell
> az disk list -g p4-dev-rg --query "[?contains(name,'OsDisk')].{name:name,gb:diskSizeGb}" -o table
> az disk delete -g p4-dev-rg -n <the OsDisk name> --yes
> ```

### `the Resource Group still contains Resources`

```
Error: deleting Resource Group "p4-dev-rg": the Resource Group still contains Resources.
* .../vaults/p4-dev-kv-tqjk4i
* .../networkSecurityGroups/p4-dev-nsg-proxy
* .../virtualNetworks/p4-dev-vnet
```

A failed apply left resources in Azure that are not in state, so `destroy` does
not know to remove them, and the provider will not delete a group containing
resources it did not create.

```powershell
az group delete -n p4-dev-rg --yes
az group show -n p4-dev-rg          # repeat until ResourceNotFound
terraform -chdir=envs/dev destroy   # clears whatever remains in state
```

> **Do not** set `prevent_deletion_if_contains_resources = false` to get past
> this, as the error suggests. That makes every future destroy sweep anything
> sharing the group, tracked or not. The check turning drift into a visible
> event is worth the occasional manual delete.

---

## Region changes

Changing `location` replaces the resource group. Do it in three steps, not one.

```powershell
# 1. tear down, and wait for the group to actually disappear
terraform -chdir=envs/dev destroy
az group show -n p4-dev-rg          # repeat until ResourceNotFound

# 2. change location in envs/dev/terraform.tfvars

# 3. apply into the new region
terraform -chdir=envs/dev apply
```

### `Root object was present, but now absent`

```
Provider produced inconsistent result after apply
... produced an unexpected new value: Root object was present, but now absent.
This is a bug in the provider ...
```

It is not a provider bug. Azure deletes resource groups **asynchronously**: the
API returns before deletion finishes. Terraform sees the delete complete,
recreates a group with the same name, and starts creating children while Azure
is still tearing the old one down. The in-flight deletion removes them.

Accompanied by, for anything with a data plane:

```
ParentResourceNotFound: ... storageAccounts/<name> could not be found
```

Fix: the three-step sequence above, waiting at step 1.

### `AlreadyExistServicePrincipalInDifferentRegion`

```
FailedIdentityOperation: ... Location mismatch in AAD and in Model.
LocationInAAD: 'canadacentral', LocationInModel: 'canadaeast'
```

A VM's system-assigned identity is a service principal in Entra ID stamped with
the VM's region, and it outlives the VM. Recreating a VM with the same resource
ID in a different region collides with it.

```powershell
az ad sp show --id <objectId from the error> `
  --query "{name:displayName, type:servicePrincipalType}" -o json
az ad sp delete --id <objectId from the error>
```

> **Caveat.** That delete usually fails with *"Insufficient privileges to
> complete the operation"*, and that is **not** a missing directory role.
> Managed-identity service principals are owned by the resource provider, not
> the directory, so Entra rejects direct deletion regardless of what roles you
> hold. Entra clears them up on its own eventually.

The reliable fix is to not collide: node names include a region code
(`p4-dev-cae-commit-01`), so resource IDs stay distinct per region. See
ARCHITECTURE.md.

---

## VM sizing

Two failures that read similarly and are not the same.

### `SkuNotAvailable ... NotAvailableForSubscription`

The subscription is never offered that size in that region. **Permanent**, and
visible in advance:

```powershell
az vm list-skus --location canadaeast --size Standard_B --all -o table
```

Rows with `NotAvailableForSubscription` cannot be deployed. Fix by changing
region, size family, or subscription type.

### `AllocationFailed ... insufficient capacity for the requested VM size`

The datacenter has no free capacity for that size **at that moment**.
Transient, and it does **not** appear in `list-skus`, which reports subscription
restrictions rather than live capacity. Nothing predicts it in advance.

Fix by retrying, or by using another size. Sizes with no subscription
restriction in canadaeast, in order worth trying:

| Size | vCPU / RAM | CPU |
|---|---|---|
| `Standard_B2ats_v2` | 2 / 8 GiB | AMD |
| `Standard_B2as_v2` | 2 / 8 GiB | AMD |
| `Standard_B2s_v2` | 2 / 8 GiB | Intel |
| `Standard_B2ls_v2` | 2 / 4 GiB | Intel |

AMD and Intel sizes draw on different hardware pools, so switching vendor often
allocates when a retry will not. `Standard_B2ts_v2` is too small (1 GiB) for
p4d with SDP.

Changing size requires the lab guardrails to permit it:

```powershell
cd ..\az104-lab
.\Deploy-Guardrails.ps1 -ContactEmail you@example.com -BudgetAmount 50
.\Test-Guardrails.ps1
```

### Architecture

x86_64 only. Perforce's apt repository publishes `binary-amd64` and
`binary-i386` for Ubuntu, and no `binary-arm64`, so every `Standard_B*p*` /
`D*p*` size (Ampere) is unusable regardless of availability.

```powershell
# check what a repository actually publishes
curl http://package.perforce.com/apt/ubuntu/dists/noble/release/
```

---

## Provisioning

### `cloud-init status` says `done, errors: []` but provisioning stopped

The exit status of a pipeline is the exit status of its **last** command. With

```yaml
- [ bash, -lc, "provision.sh ARGS 2>&1 | tee /var/log/p4-provision.log" ]
```

the status is `tee`'s, which is always 0, so a failing script reports success
and cloud-init records no error. Set `pipefail`:

```yaml
- [ bash, -lc, "set -o pipefail; stdbuf -oL -eL provision.sh ARGS 2>&1 | tee /var/log/p4-provision.log; echo \"provision.sh exit=$?\" | tee -a /var/log/p4-provision.log" ]
```

`stdbuf -oL` matters too: writing to a pipe makes libc block-buffer stdout, so
the log appears in 4 KB chunks and the last thing it shows is not necessarily
where the script stopped.

### The log just stops, with no error

`set -e` exits silently. Add an ERR trap so the failing line reports itself:

```bash
trap 'echo "[script] FAILED at line $LINENO: $BASH_COMMAND" >&2' ERR
```

A specific trap for this: a function whose **last command** is a test.

```bash
resolve_lun() {
  ...
  [[ -b "$dev" ]] && echo "$dev"     # returns 1 when the test is false
}
dev="$(resolve_lun "$lun")"          # assignment takes the substitution's status
                                     # -> set -e aborts the whole script
```

Add an explicit `return 0` when the condition is a normal outcome rather than an
error.

### Running provisioning by hand

Faster than re-applying to test a change:

```powershell
az vm run-command invoke -g p4-dev-rg -n p4-dev-cae-commit-01 `
  --command-id RunShellScript `
  --scripts "bash -x /opt/p4-provisioning/common/volumes.sh commit 2>&1 | tail -60"
```

Set the environment the script expects first if it reads any:

```powershell
--scripts "export DISK_MAP='p4db=0,p4db2=1,p4logs=2,p4depots=3'; bash -x /opt/p4-provisioning/common/volumes.sh commit 2>&1 | tail -60"
```

`bash -x` prints each command before running it, which locates the stop
precisely.

### Provisioning works by hand but not during boot

Symptom: the script stops partway through cloud-init, but running the same
script over `run-command` afterwards completes without error.

Cause: cloud-init's `runcmd` fires before the Azure agent has finished
publishing `/dev/disk/azure/scsi1/lunN` for every attached data disk. Early in
boot only some LUNs exist, so anything resolving a disk by LUN sees a partial
set. By the time you run it by hand, all of them are there, so the failure
cannot reproduce.

`volumes.sh` now waits for each LUN named in `DISK_MAP`, up to
`LUN_WAIT_SECONDS` (default 120), calling `udevadm settle` on the first miss. A
LUN that never appears is treated as a failure rather than skipped, because
every entry in `DISK_MAP` is a disk Terraform attached.

The general shape is worth remembering: anything in `runcmd` that depends on
hardware enumeration, network readiness, or another agent's work needs to wait
for it. Boot-time races do not reproduce interactively.

### `mkfs.xfs: command not found`

`xfsprogs` is not guaranteed on a cloud image. It is in the base package list in
`provisioning/common/packages.sh`; if a role skips package installation, the
format step fails.

---

## Windows

### `].{name:name was unexpected at this time`

```powershell
# fails
az policy assignment list --query "[?starts_with(name,'az104')].{name:name}" -o table
```

`az` on Windows is `az.cmd`, a batch wrapper that re-expands its arguments
through cmd, and cmd treats parentheses as syntax. Queries **without**
parentheses are fine, so `--query "[].name" -o tsv` still works.

Ask for JSON and filter in PowerShell:

```powershell
az policy assignment list -o json | ConvertFrom-Json |
  Where-Object { $_.name -like 'az104*' } |
  Select-Object name, displayName, enforcementMode | Format-Table
```

### `NativeCommandError` from a command that succeeded

```
az.cmd : WARNING: This command is in preview ...
+ CategoryInfo : NotSpecified: (...) [], RemoteException
```

Several `az` commands write informational text to **stderr** on success:
preview notices, CLI upgrade notices, extension prompts. Capturing with `2>&1`
turns those into PowerShell error records, and under
`$ErrorActionPreference = 'Stop'` they terminate the script.

Keep the streams apart and judge success by the exit code:

```powershell
$errFile = [System.IO.Path]::GetTempFileName()
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
try   { $raw = & az @Arguments -o json 2>$errFile; $code = $LASTEXITCODE }
finally { $ErrorActionPreference = $prev }
if ($code -ne 0) { throw (Get-Content $errFile -Raw) }
($raw -join "`n") | ConvertFrom-Json
```

### A script prints its own source, or sections vanish

```
On â€ services are disabled ... -ForegroundColor Green }
```

Windows PowerShell 5.1 reads `.ps1` files using the system ANSI code page
unless the file has a UTF-8 BOM. A UTF-8 em-dash is read as two bytes, breaking
string quoting -- the script still parses, so nothing catches it until runtime.

Keep `.ps1` files pure ASCII: `--` rather than an em-dash, straight quotes.

```powershell
.\scripts\Test-ScriptEncoding.ps1     # fails on any non-ASCII in a .ps1
```

Runs as part of `ci-checks.ps1`.

### `Program 'pip.exe' failed to run: An Application Control policy has blocked this file`

Smart App Control or WDAC blocking an unsigned executable. `pip.exe` exists;
Windows refuses to run it. Downloaded release binaries are usually refused for
the same reason, so downloading harder does not help.

```powershell
.\scripts\setup-env.ps1 -Diagnose    # reports Smart App Control / WDAC state
```

winget packages are signed and install under such a policy, which is why
`setup-env.ps1` tries winget first and falls back to a release download only
when there is no winget package.

`checkov` has no signed Windows installer, so under an active policy it cannot
be installed from a script at all. It is optional locally and the pipeline runs
it on Linux:

```powershell
.\scripts\ci-checks.ps1 -SkipScan
```

### A tool installed but the command is not found

pip writes console scripts to the per-user Scripts directory, which Windows does
not put on PATH:

```
C:\Users\<you>\AppData\Roaming\Python\Python310\Scripts
```

Ask Python where it is rather than guessing at the version-specific path:

```powershell
python -c "import sysconfig;print(sysconfig.get_path('scripts', scheme='nt_user'))"
```

`ci-checks.ps1` prepends it per run. To make it permanent:

```powershell
[Environment]::SetEnvironmentVariable('PATH',
  [Environment]::GetEnvironmentVariable('PATH','User') + ';<that path>', 'User')
```

winget shims have a related problem: they do not appear in an **already running**
process. `setup-env.ps1` re-reads PATH from the registry before deciding an
install failed.
