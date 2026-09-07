# Default-deny segmentation. Each rule below is an explicit, directional
# allow. No Perforce host has a public IP in any environment.

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each             = var.subnet_prefixes
  name                 = each.key == "mgmt" ? "AzureBastionSubnet" : "${var.name_prefix}-snet-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value]
}

resource "azurerm_network_security_group" "this" {
  for_each            = toset(["commit", "edge", "proxy", "app"])
  name                = "${var.name_prefix}-nsg-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# --- commit: accepts p4d only from edge, proxy and app tiers ---------------
resource "azurerm_network_security_rule" "commit_in" {
  for_each = {
    edge  = { prio = 100, src = var.subnet_prefixes["edge"] }
    proxy = { prio = 110, src = var.subnet_prefixes["proxy"] }
    app   = { prio = 120, src = var.subnet_prefixes["app"] }
  }
  name                        = "allow-p4d-from-${each.key}"
  priority                    = each.value.prio
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.p4_port)
  source_address_prefix       = each.value.src
  destination_address_prefix  = var.subnet_prefixes["commit"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this["commit"].name
}

resource "azurerm_network_security_rule" "commit_deny_all_in" {
  name                        = "deny-all-inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this["commit"].name
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = azurerm_network_security_group.this
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = each.value.id
}
