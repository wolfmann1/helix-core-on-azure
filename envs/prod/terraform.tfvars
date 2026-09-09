# prod — the full topology, sized for CAPABILITY not throughput.
# Every VM here is the smallest SKU that will actually run its role. The point
# is to prove the architecture and exercise a real failover, not to serve load.
location        = "canadaeast"
# canadacentral has no x86 capacity on this subscription, so the standby cannot
# live there. westus2 was added to allowedLocations in az104-lab/guardrails.bicep
# for this. Verify capacity before a prod apply:
#   az vm list-skus --location westus2 --size Standard_B --all -o table
# Note this puts the DR copy in the US. Fine for a lab; for a real estate,
# confirm the customer accepts their depot content leaving Canada.
dr_location     = "westus2"
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

# prod is the one environment where a deleted vault should be recoverable.
# Note this is one-way: Azure does not allow purge protection to be disabled
# once a vault has it.
key_vault_purge_protection = true
