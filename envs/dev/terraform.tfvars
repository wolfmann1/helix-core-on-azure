location       = "canadacentral"
alert_email    = "clesemann@gmail.com"
ssh_public_key = "ssh-ed25519 REPLACE_ME"
install_sdp    = true

# OS is pinned by modules/p4-node's os_image default: Ubuntu 24.04 LTS.
# That is the newest Ubuntu P4 Code Review (Swarm) supports; 26.04 is not
# supported and the module's validation block rejects it.
