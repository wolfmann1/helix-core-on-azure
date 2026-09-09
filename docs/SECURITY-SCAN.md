# checkov findings and how they were handled

First scan: 165 passed, 49 failed. Getting a scanner to zero is not the goal;
deciding which findings apply to this environment is. Every suppression below is
an inline `checkov:skip` with its reason next to the resource, so the reasoning
travels with the code rather than sitting in a separate allow-list.

## Fixed

| Check | Resource | Change |
|---|---|---|
| CKV2_AZURE_40 | checkpoint storage account | `shared_access_key_enabled = false`. Node identities write through RBAC, so no account key is needed. The state account already had this. |
| CKV_AZURE_109 | Key Vault | `network_acls` with `default_action = "Deny"` and `bypass = "AzureServices"`. |
| CKV2_AZURE_41 | both storage accounts | `sas_policy` with a one-hour expiration and logging. |
| CKV_AZURE_251 | managed disks | `public_network_access_enabled = false`. Disks are reached over the VNet. |

## Accepted, with the reason recorded in the code

| Check | Why |
|---|---|
| CKV_AZURE_206 (replication) | LRS is a deliberate cost choice for an environment that is rebuilt often. `checkpoint_replication` is a variable; set GRS for anything holding real depot content. |
| CKV2_AZURE_1, CKV_AZURE_93 (customer-managed keys) | Would require a Key Vault key, rotation policy and disk encryption set. Platform-managed keys are appropriate here. |
| CKV_AZURE_33, CKV2_AZURE_21 (queue and blob read logging) | These accounts hold blobs only, and read logging on a checkpoint container has no audience in a lab. |
| CKV_AZURE_50 (VM extensions) | No extensions are installed. Configuration goes through cloud-init and `provisioning/`, which is what keeps the Hyper-V path working. |
| CKV_AZURE_59, CKV2_AZURE_33 (state account public access) | The GitHub Actions runners reach the state account over the internet. A private endpoint would require a self-hosted runner inside the VNet. Anonymous access is off and account keys are disabled, so access requires an Entra ID identity. |
| CKV2_AZURE_31 (subnet NSG) | The commit, edge, proxy and app subnets each have an NSG associated; the graph check does not resolve the `for_each`. AzureBastionSubnet genuinely has none — see below. |

## Real gaps, not yet closed

**Private endpoints (CKV2_AZURE_32, CKV2_AZURE_33 on the checkpoint account).**
The build spec claimed the network module created private endpoints for the Key
Vault and the storage account. It did not. Public network access is disabled on
both, which closes the exposure, but it also means nodes inside the VNet cannot
reach either service until the endpoints and their private DNS zones exist. The
spec has been corrected and the work is a TODO in `modules/storage`.

**NSG on AzureBastionSubnet (CKV2_AZURE_31).** Bastion requires a specific
inbound rule set — GatewayManager and AzureLoadBalancer on 443, plus the control
plane ports — and an NSG missing any of them disables the service rather than
degrading it. Worth building deliberately. TODO in `modules/network`.

## Running the scan

```powershell
.\scripts\ci-checks.ps1              # includes checkov when it is installed
.\scripts\ci-checks.ps1 -SkipScan    # skip it for a faster inner loop
```

The pipeline runs checkov on every pull request regardless of what is installed
locally.
