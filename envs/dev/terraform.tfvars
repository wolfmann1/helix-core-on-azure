location       = "canadacentral"
alert_email    = "clesemann@gmail.com"
ssh_public_key = "ssh-ed25519 REPLACE_ME"
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
