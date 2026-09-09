variable "name" {
  description = "Node name, e.g. p4-dev-commit-01."
  type        = string
}

variable "role" {
  description = "Perforce role. Drives package selection, volume layout and provisioning."
  type        = string
  validation {
    condition     = contains(["commit", "edge", "proxy", "broker", "standby", "swarm", "p4search"], var.role)
    error_message = "role must be one of: commit, edge, proxy, broker, standby, swarm, p4search."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the node."
  type        = string
}

variable "subnet_id" {
  description = "Subnet the NIC attaches to."
  type        = string
}

variable "vm_size" {
  description = <<-EOT
    Azure VM size. The default is the smallest B v2 SKU permitted by the
    az104-lab guardrails.

    B-series v1 (Standard_B1s, Standard_B2s) is announced for retirement on
    15 November 2028; VMs on those sizes are deallocated at that point. B v2
    is the recommended replacement, so this configuration uses it throughout.

    x86_64 is required. Perforce's apt repository publishes only binary-amd64
    and binary-i386 for Ubuntu; there is no binary-arm64, so p4d cannot be
    installed from the vendor repository on an Ampere VM. Every Standard_B*p*
    size is ARM64 and is therefore unusable here regardless of what the lab
    policy permits.
  EOT
  type        = string
  default     = "Standard_B2ats_v2"
}

variable "os_image" {
  description = <<-EOT
    Marketplace image. Must be an OS that P4 Code Review (Swarm) supports,
    because Swarm is the binding constraint for the whole estate.

    Supported as of Swarm 2026.3: Ubuntu 22.04 / 24.04 LTS, RHEL 8 / 9,
    Rocky Linux 8 / 9. Ubuntu 26.04 is NOT supported and is rejected by the
    validation below rather than failing later during provisioning.

    RHEL 9 alternative:
      os_image = {
        publisher = "RedHat"
        offer     = "RHEL"
        sku       = "9-lvm-gen2"
        version   = "latest"
      }
  EOT
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  validation {
    condition = contains([
      "ubuntu-24_04-lts",
      "ubuntu-22_04-lts",
      "RHEL",
      "rockylinux-x86_64",
    ], var.os_image.offer)
    error_message = "os_image.offer must be an OS supported by P4 Code Review: Ubuntu 22.04/24.04 LTS, RHEL 8/9, or Rocky Linux 8/9. Ubuntu 26.04 is not supported."
  }
}

variable "disk_tier" {
  description = <<-EOT
    Managed disk type for all data disks on this node.

      premium    -> Premium_LRS      (Premium SSD v1, minimum 4 GiB)
      standard   -> StandardSSD_LRS  (Standard SSD, minimum 4 GiB)  [default]
      premium_v2 -> PremiumV2_LRS    (Premium SSD v2, minimum 1 GiB)
      hdd        -> Standard_LRS     (Standard HDD, minimum 32 GiB)

    Premium SSD v2 is the only type that honours sizes below 4 GiB, but it
    cannot use host caching and, in most regions with availability zones, can
    only attach to a zonal VM. Set var.zone when using it.

    Sizes smaller than the selected type's minimum are rounded up rather than
    rejected, so a teardown-and-rebuild cycle does not fail on a size that
    Azure will not allocate.
  EOT
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["premium", "standard", "premium_v2", "hdd"], var.disk_tier)
    error_message = "disk_tier must be one of: premium, standard, premium_v2, hdd."
  }
}

variable "disk_sizes_gb" {
  description = <<-EOT
    Per-volume size overrides in GiB. Unset volumes use the defaults below,
    which are sized for a lab that is built up and torn down repeatedly:

      p4db     2   metadata, db.* files
      p4db2    2   second metadata volume (see split_metadata)
      p4logs   2   journal and structured logs
      p4depots 5   versioned archive files
      p4       1   SDP root, when separate_sdp_volumes is true
      p4ckps   1   checkpoints, when separate_sdp_volumes is true

    p4serverlocks is not in this map. It is a tmpfs in RAM, not a disk; its
    size is set by var.serverlocks_tmpfs_mb.
  EOT
  type        = map(number)
  default     = {}
}

variable "split_metadata" {
  description = "Place metadata on two volumes (p4db and p4db2) rather than one. SDP supports splitting db.* files across two metadata volumes; set false for a single shared metadata disk."
  type        = bool
  default     = true
}

variable "separate_sdp_volumes" {
  description = "Give /p4 (SDP root) and /p4ckps (checkpoints) their own volumes rather than placing them on p4depots. Off by default because it adds two disks to every node."
  type        = bool
  default     = false
}

variable "serverlocks_tmpfs_mb" {
  description = "Size of the tmpfs mounted for server lock files. SDP recommends placing server.locks in RAM. Set to 0 to skip the tmpfs entirely."
  type        = number
  default     = 1024
}

variable "zone" {
  description = "Availability zone for the VM and its disks. Required when disk_tier is premium_v2 in most regions."
  type        = string
  default     = null
}

variable "install_sdp" {
  description = "Install the Perforce Server Deployment Package. Exposed as a parameter so a plain p4d can be deployed for comparison."
  type        = bool
  default     = true
}

variable "sdp_instance" {
  description = "SDP instance name/number."
  type        = string
  default     = "1"
}

variable "commit_host" {
  description = "Hostname or IP of the commit server. Required for every role except commit."
  type        = string
  default     = ""
}

variable "p4_port" {
  description = "TCP port p4d listens on."
  type        = number
  default     = 1666
}

variable "admin_username" {
  description = "Local admin account name for SSH."
  type        = string
  default     = "p4admin"
}

variable "ssh_public_key" {
  description = "SSH public key. Password authentication is disabled in all cases."
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault the node's managed identity is granted read access to. Only used when grant_key_vault_access is true."
  type        = string
  default     = ""
}

variable "grant_key_vault_access" {
  description = <<-EOT
    Grant this node's managed identity the Key Vault Secrets User role on
    var.key_vault_id.

    This is a separate flag rather than a test of key_vault_id because the id
    comes from the Key Vault resource and is unknown at plan time, and count
    cannot depend on a value Terraform does not yet know.
  EOT
  type    = bool
  default = false
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
