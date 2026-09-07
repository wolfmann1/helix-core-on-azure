# Getting started

## 0. Tooling

**PowerShell (the primary path here):**
```powershell
.\scripts\setup-env.ps1 -Check   # what's missing
.\scripts\setup-env.ps1          # install into .\.tools
```

**bash / WSL / CI:**
```bash
./scripts/setup-env.sh --check
./scripts/setup-env.sh
```

Versions are pinned in `dependencies.txt`; both scripts read the same file.

## 1. Azure prerequisites (yours, not Terraform's)

1. An Azure subscription and `az login`.
2. An Entra ID app registration with a **federated credential** for this GitHub
   repo (subject `repo:<owner>/<repo>:environment:dev`, etc.). No client secret.
3. Grant that app Contributor on the subscription, or narrower.
4. Set repo **variables** (not secrets): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID`.
5. Create GitHub **Environments** named `dev`, `stage`, `prod`. Add required
   reviewers to `stage` and `prod` — that is the approval gate.

## 2. Bootstrap state

```bash
cd bootstrap && terraform init && terraform apply
```
Copy the `storage_account_name` output into every `envs/*/backend.tf`.

## 3. First environment

```bash
terraform -chdir=envs/dev init
terraform -chdir=envs/dev plan
```

Set `ssh_public_key` in `envs/dev/terraform.tfvars` first.

## 4. Free alternative

`local/hyperv/New-P4Lab.ps1` builds the same estate on Hyper-V using the same
provisioning scripts and costs nothing. Develop there, prove in Azure.

## Status

This scaffold has **not** been run through `terraform validate` — there was no
Terraform binary available when it was generated. Step one:

```powershell
.\scripts\ci-checks.ps1                 # dev
.\scripts\ci-checks.ps1 -Environment prod
.\scripts\ci-checks.ps1 -SkipScan       # fast inner loop
```

Expect to fix things. Resource blocks marked `TODO(chris)` are intentionally
unimplemented; they are the parts worth building by hand rather than reading.

`ci-checks.ps1` and `ci-checks.sh` run the same sequence. The pipeline uses the
`.sh` version because GitHub runners are Linux, so a failure locally is a
failure in CI. **If you change one, change both** — a divergence between them is
worse than having only one.
