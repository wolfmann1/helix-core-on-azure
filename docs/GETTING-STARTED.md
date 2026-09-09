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
