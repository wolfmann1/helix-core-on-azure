# Local Hyper-V lab

Runs the same estate locally, without Azure spend.

Terraform creates infrastructure and `provisioning/` configures it, and nothing
under `provisioning/` references Azure. Hyper-V therefore reuses
`provisioning/provision.sh` unchanged: the same commit server, the same
three-volume layout, the same SDP parameter.

## What it builds

| VM | vCPU | RAM | Disks |
|---|---|---|---|
| p4-commit-01 | 2 | 4 GB | os 32G, p4db 16G, p4logs 16G, p4depots 32G |
| p4-edge-01 (optional) | 2 | 4 GB | same |
| p4-proxy-01 (optional) | 1 | 2 GB | os 32G, p4depots 32G |
| p4-swarm-01 (optional) | 2 | 4 GB | os 32G |

Around 20 GB of RAM to run everything; the commit server alone runs in 4.

## When to use the local lab

- Iterating on `provisioning/`, where the feedback loop is seconds rather than
  minutes and costs nothing
- Practising checkpoint restore and failover repeatedly
- When Azure credits are limited

## When to use Azure

- Exercising managed identity, Key Vault and OIDC, which is most of what the
  job postings ask about
- Cross-region standby, which needs two regions
- Producing evidence for the portfolio

## On-demand versus always-on

The split that works in practice:

- **Always on, locally:** the Hyper-V commit server. No cost, and it is where
  development happens.
- **On demand, in Azure:** `envs/stage` and `envs/prod`. Apply, capture the
  evidence (alert screenshots, plan output, failover timings), then destroy with
  `scripts/teardown.ps1`.

This keeps credits available for the things only Azure demonstrates.
