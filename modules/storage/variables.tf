variable "name_prefix" {
  description = "Prefix for storage resource names."
  type        = string
}
variable "location" {
  description = "Azure region."
  type        = string
}
variable "resource_group_name" {
  description = "Resource group for storage resources."
  type        = string
}
variable "checkpoint_replication" {
  description = "Replication for the offsite checkpoint account. GRS in prod; LRS is enough for a lab."
  type        = string
  default     = "LRS"
}
variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
