# Getting started

## 0. Tooling

```bash
./scripts/setup-env.sh --check   # what's missing
./scripts/setup-env.sh           # install into ./.tools
```
Windows: `.\scripts\setup-env.ps1`. Versions are pinned in `dependencies.txt`.

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
Terraform binary available when it was generated. Step one is
`./scripts/ci-checks.sh dev`, and expect to fix things. Resource blocks marked
`TODO(chris)` are intentionally unimplemented; they are the parts worth building
by hand rather than reading.
