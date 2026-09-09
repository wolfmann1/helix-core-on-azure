# Changing this replaces the resource group. Do not change it and apply in one
# step: Azure deletes resource groups asynchronously, and the in-flight deletion
# will remove resources the same apply just created. Destroy first, confirm the
# group is gone with "az group show -n p4-dev-rg", then change and apply.
# See docs/GETTING-STARTED.md.
location       = "canadaeast"
alert_email    = "clesemann@gmail.com"
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKPVLh9iBBzprRNCe+JzTc4OAk8ZQbMlwaPO8vH+9Kmd juwel@cl-gaming-pc"
install_sdp    = true

# OS is pinned by modules/p4-node's os_image default: Ubuntu 24.04 LTS.
# That is the newest Ubuntu P4 Code Review (Swarm) supports; 26.04 is not
# supported and the module's validation block rejects it.

# Disk configuration.
#
# disk_tier "standard" (Standard SSD) is the cheapest type that still honours
# small sizes. Azure's smallest Standard SSD and Premium SSD v1 tiers are both
# 4 GiB, so the 2 GiB defaults below are rounded up to 4 GiB automatically.
# Use "premium_v2" if the exact 2 GiB allocation matters; it requires a zonal
# VM and does not support host caching.
disk_tier = "standard"

# Perforce lab defaults, applied when this map is empty:
#   p4db 2, p4db2 2, p4logs 2, p4depots 5, p4 1, p4ckps 1  (GiB)
disk_sizes_gb = {}

split_metadata       = true  # p4db + p4db2; false gives one shared metadata disk
separate_sdp_volumes = false # true adds /p4 and /p4ckps as their own volumes
serverlocks_tmpfs_mb = 1024  # server.locks in RAM; 0 to skip

# Standard_B2ats_v2 was refused in canadacentral with "SkuNotAvailable ...
# Capacity Restrictions" on 2026-09-09. Being allowed by policy is not the same
# as having capacity, and capacity varies by region, zone and subscription type.
# Check what is actually deployable before changing this:
#   az vm list-skus --location canadacentral --size Standard_B --all -o table
# Region checked 2026-09-09. On this subscription canadacentral has no x86
# capacity at all: every x86 B-series and D-series size is
# NotAvailableForSubscription, leaving only Standard_B*p* / D*p* (ARM64) and
# confidential-compute sizes. ARM cannot run p4d because Perforce publishes no
# arm64 packages, so canadacentral is unusable for this estate.
#
# canadaeast has the x86 B-series v2 sizes unrestricted, so that is the region
# used here. Both regions are permitted by the az104-lab guardrails.
