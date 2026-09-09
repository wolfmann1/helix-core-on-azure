# prod — the full topology, sized for CAPABILITY not throughput.
# Every VM here is the smallest SKU that will actually run its role. The point
# is to prove the architecture and exercise a real failover, not to serve load.
location        = "canadaeast"
# TODO(chris): the cross-region standby needs a second region that can host
# x86 VMs. canadacentral cannot on this subscription, so the two regions the
# guardrails permit are no longer enough for a DR demonstration. Either widen
# allowedLocations in az104-lab/guardrails.bicep to a third region after
# checking it with az vm list-skus, or accept that failover cannot be exercised
# here. Left pointing at canadacentral so a prod apply fails loudly rather than
# deploying a standby that cannot be created.
dr_location     = "canadacentral"
alert_email     = "clesemann@gmail.com"
ssh_public_key  = "ssh-ed25519 REPLACE_ME"
edge_count      = 1
proxy_sites     = { vancouver = { vm_size = "Standard_B2ats_v2" }, montreal = { vm_size = "Standard_B2ats_v2" } }
enable_swarm    = true
enable_p4search = false # Elasticsearch floor is 4 vCPU / 8GB per component — turn on deliberately
enable_standby  = true
install_sdp     = true

# Disk configuration. prod uses premium disks and separate SDP volumes so the
# topology matches a real deployment; sizes stay small because this environment
# is built up and torn down rather than run continuously.
disk_tier            = "premium"
disk_sizes_gb        = { p4db = 8, p4db2 = 8, p4logs = 8, p4depots = 32 }
split_metadata       = true
separate_sdp_volumes = true
serverlocks_tmpfs_mb = 1024
zone                 = "1"
