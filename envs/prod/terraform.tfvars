# prod — the full topology, sized for CAPABILITY not throughput.
# Every VM here is the smallest SKU that will actually run its role. The point
# is to prove the architecture and exercise a real failover, not to serve load.
location        = "canadacentral"
dr_location     = "canadaeast"
alert_email     = "clesemann@gmail.com"
ssh_public_key  = "ssh-ed25519 REPLACE_ME"
edge_count      = 1
proxy_sites     = { vancouver = { vm_size = "Standard_B1ms" }, montreal = { vm_size = "Standard_B1ms" } }
enable_swarm    = true
enable_p4search = false # Elasticsearch floor is 4 vCPU / 8GB per component — turn on deliberately
enable_standby  = true
install_sdp     = true
