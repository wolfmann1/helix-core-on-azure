location       = "canadacentral"
alert_email    = "clesemann@gmail.com"
ssh_public_key = "ssh-ed25519 REPLACE_ME"
edge_count     = 1
proxy_sites    = { vancouver = { vm_size = "Standard_B1ms" } }
enable_swarm   = true
install_sdp    = true

disk_tier            = "standard"
disk_sizes_gb        = {}
split_metadata       = true
separate_sdp_volumes = false
serverlocks_tmpfs_mb = 1024
