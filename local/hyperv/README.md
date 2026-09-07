# Local Hyper-V lab

The credit-free option. Same provisioning scripts, no Azure spend.

This exists because the Azure/Hyper-V split was designed in from the start:
Terraform creates **infrastructure**, `provisioning/` creates **configuration**,
and nothing in `provisioning/` knows what a resource group is. Hyper-V therefore
reuses `provisioning/provision.sh` verbatim — the same commit server, the same
three-volume split, the same SDP parameter.

## What you get

| VM | vCPU | RAM | Disks |
|---|---|---|---|
| p4-commit-01 | 2 | 4 GB | os 32G, p4db 16G, p4logs 16G, p4depots 32G |
| p4-edge-01 (optional) | 2 | 4 GB | same |
| p4-proxy-01 (optional) | 1 | 2 GB | os 32G, p4depots 32G |
| p4-swarm-01 (optional) | 2 | 4 GB | os 32G |

Roughly 20 GB RAM if you run everything; the commit server alone runs in 4.

## Use it when

- Iterating on `provisioning/` — the feedback loop is seconds, not minutes,
  and it costs nothing
- Practising checkpoint restore and failover repeatedly
- Azure credits are running low

## Use Azure when

- You need the managed identity / Key Vault / OIDC story, which is most of
  what the job postings are asking about
- You are exercising cross-region standby, which needs two regions
- You are producing evidence for the portfolio

## Choosing on-demand vs always-on

You do not have to decide globally. The split that works:

- **Always on, locally:** the Hyper-V commit server. Free, and it is where you
  develop.
- **On demand, in Azure:** `envs/stage` and `envs/prod`. Apply, capture the
  evidence (screenshots, plan output, alert firing, a failover drill), destroy.
  `scripts/teardown.sh` exists for exactly this.

That keeps credits for the things only Azure can prove.
