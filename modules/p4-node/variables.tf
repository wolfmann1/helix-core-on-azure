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
  description = "Azure VM size. Defaults are the smallest that will actually run the role — this repo optimises for capability, not throughput."
  type        = string
  default     = "Standard_B2s"
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

variable "data_disks" {
  description = "Data disks to attach, keyed by volume label (p4db, p4logs, p4depots). The label is what provisioning/common/volumes.sh mounts by."
  type = map(object({
    size_gb = number
    tier    = string
    lun     = number
  }))
  default = {}
}

variable "install_sdp" {
  description = "Install the Perforce Server Deployment Package. Exposed as a parameter so a plain p4d can be stood up for comparison."
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
  description = "SSH public key. Password auth is disabled unconditionally."
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault the node's managed identity is granted read access to."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
