# Getting started

## 0. Tooling

PowerShell:

```powershell
.\scripts\setup-env.ps1 -Check   # report what is missing
.\scripts\setup-env.ps1          # install into .\.tools
```

bash, WSL or CI:

```bash
./scripts/setup-env.sh --check
./scripts/setup-env.sh
```

Versions are pinned in `dependencies.txt`. Both scripts read the same file.

On Windows the script tries winget first and falls back to downloading the
release asset into `.\.tools\bin`. winget packages are signed, which matters on
a machine running Smart App Control or WDAC: those policies block unsigned
executables, including loose binaries from a release page and the `pip.exe`
shim.

`checkov` has no signed Windows installer. Where an Application Control policy
is active it cannot be installed locally at all, and `ci-checks.ps1` skips the
scan step with a note. The pipeline runs checkov on Linux, so the scan still
happens on every pull request.

`.\scripts\setup-env.ps1 -Diagnose` reports whether such a policy is active and
where each tool resolves from.

## 1. Azure prerequisites

These are manual steps, not managed by Terraform.

1. An Azure subscription, and `az login`.
2. An Entra ID app registration with a federated credential for this GitHub
   repository (subject `repo:<owner>/<repo>:environment:dev`, and one per
   environment). No client secret is required.
3. Grant that app Contributor on the subscription, or a narrower scope.
4. Set repository variables (not secrets): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID`.
5. Create GitHub Environments named `dev`, `stage` and `prod`. Add required
   reviewers to `stage` and `prod`; this is what enforces the approval gate.

## 2. Bootstrap the state backend

```bash
cd bootstrap && terraform init && terraform apply
```

Copy the `storage_account_name` output into each `envs/*/backend.tf`.

This configuration is applied once, by hand, with local state, because the state
backend cannot store its own state.

It also grants **Storage Blob Data Contributor** on the state account to whoever
runs it. That is not optional: the backend uses `use_azuread_auth` and the
account has `shared_access_key_enabled = false`, so Terraform reaches the blob
data plane as the signed-in principal. Control-plane roles such as Owner do not
grant data-plane access, and without the assignment `terraform init` in `envs/*`
fails with a 403 on the state container.

The pipeline's OIDC identity needs the same role. Grant it once after step 1:

```powershell
$sa = az storage account list -o json | ConvertFrom-Json |
      Where-Object { $_.name -like 'p4tfstate*' }
az role assignment create `
  --role "Storage Blob Data Contributor" `
  --assignee <the app registration's object id> `
  --scope $sa.id
```

Role assignments can take a couple of minutes to take effect. `bootstrap` and
`modules/storage` both wait 60 seconds after assigning the role before making
the first data-plane call, because RBAC is eventually consistent and a container
create straight after the assignment still returns 403.

### If the first apply failed partway

The first attempt at this configuration failed on
`KeyBasedAuthenticationNotPermitted` while waiting for the storage account's
data plane. Three outcomes are possible, so check state first:

```powershell
terraform state list
```

**1. The account is in state and tainted.** This is the usual outcome. Terraform
taints a resource whose create failed partway, and a tainted resource is always
planned as destroy-and-recreate -- which `prevent_destroy` then refuses, with
"Instance cannot be destroyed".

The account itself is fine; only its post-create configuration (versioning,
retention, tags) did not finish, and all of that is updatable in place. Clear
the taint and let the next apply converge it:

```powershell
terraform untaint azurerm_storage_account.state
terraform plan     # should now be "update in-place", not "destroy and then create"
terraform apply
```

Do not work around this by removing `prevent_destroy`. It stopped a
destroy-and-recreate of the account holding state for every environment, which
is what it is there for.

**2. Not in state, but present in Azure.** Adopt it rather than deleting it --
`random_string` is in state and regenerates the same suffix, and storage account
names are globally unique and not immediately reusable after a delete:

```powershell
az storage account list -o json | ConvertFrom-Json |
  Where-Object { $_.name -like 'p4tfstate*' } | Select-Object name, id

terraform import azurerm_storage_account.state "<the id>"
terraform apply
```

**3. Not in state and not in Azure.** Re-run `terraform apply`.

Note that `az storage account list` can lag a failed create by a minute or two
and report nothing while the account exists. `terraform state list` and a
refresh are the more reliable check.

### Changing an environment's region

A region change replaces the resource group, and that is not safe to do in a
single apply. Azure deletes a resource group **asynchronously**: the API returns
before the deletion has finished. Terraform sees the delete complete, recreates
a group with the same name, and starts creating children while Azure is still
tearing the old one down. The in-flight deletion removes the new resources and
the apply fails with:

```
Provider produced inconsistent result after apply
... produced an unexpected new value: Root object was present, but now absent.
```

and, for anything with a data plane:

```
ParentResourceNotFound: ... storageAccounts/<name> could not be found
```

Neither is a provider bug, though the first message says so.

Do it in three steps instead, confirming Azure has finished between each:

```powershell
# 1. tear down, and wait for the group to actually disappear
terraform -chdir=envs/dev destroy
az group show -n p4-dev-rg      # repeat until this returns ResourceNotFound

# 2. change location in envs/dev/terraform.tfvars

# 3. apply into the new region
terraform -chdir=envs/dev apply
```

If an apply already failed this way, state now holds resources that no longer
exist. `destroy` reconciles that -- it refreshes, finds them gone, and drops
them from state.

The reverse also happens: a failed apply can leave resources in Azure that are
**not** in state, because the apply errored before recording them. `destroy`
then does not know about them, and deleting the resource group fails with:

```
Error: deleting Resource Group "p4-dev-rg": the Resource Group still contains Resources.
```

That check is deliberate -- the provider will not sweep resources it did not
create. Keep it on: it turns drift into a visible event. Clear the group by hand
instead:

```powershell
az group delete -n p4-dev-rg --yes
az group show -n p4-dev-rg      # repeat until ResourceNotFound
```

Do not disable `prevent_deletion_if_contains_resources` to get past it. That
flag makes every future destroy sweep anything sharing the group, tracked or
not.

#### Managed identity left behind in the old region

A VM with a system-assigned identity has a service principal in Entra ID,
stamped with the region the VM was in. Deleting the VM does not always delete
that principal promptly. Recreating a VM with the same resource ID -- same
subscription, resource group and name -- in a different region then fails:

```
FailedIdentityOperation: ... [AlreadyExistServicePrincipalInDifferentRegion]:
Location mismatch in AAD and in Model. LocationInAAD: 'canadacentral',
LocationInModel: 'canadaeast'
```

Confirm the principal belongs to the deleted VM, then remove it:

```powershell
az ad sp show --id <objectId from the error> --query "{name:displayName, type:servicePrincipalType}" -o json
az ad sp delete --id <objectId from the error>
```

`displayName` should match the VM name and `servicePrincipalType` should be
`ManagedIdentity`. Entra clears these up on its own eventually, and renaming the
VM also avoids the collision, but deleting the orphan is the direct fix.

This is worth knowing before a region migration of anything using managed
identities: the identity is a directory object with its own lifecycle, and it
does not move with the resource.

## 3. First environment

Set `ssh_public_key` in `envs/dev/terraform.tfvars`, then:

```bash
terraform -chdir=envs/dev init
terraform -chdir=envs/dev plan
```

## 4. Local alternative

`local/hyperv/New-P4Lab.ps1` builds the same estate on Hyper-V using the same
provisioning scripts, at no cost.

## Current status

This configuration has not yet been through `terraform validate`; no Terraform
binary was available when it was generated. Start with:

```powershell
.\scripts\ci-checks.ps1                  # dev
.\scripts\ci-checks.ps1 -Environment prod
.\scripts\ci-checks.ps1 -SkipScan        # faster inner loop
```

Expect to fix errors on the first run. Blocks marked `TODO(chris)` are
intentionally unimplemented and are the parts worth writing by hand.

`ci-checks.ps1` and `ci-checks.sh` run the same sequence. The pipeline uses the
bash version because GitHub runners are Linux, so a local failure predicts a CI
failure. Update both when you change either.
