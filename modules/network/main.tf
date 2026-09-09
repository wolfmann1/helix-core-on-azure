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
  # A private subnet gets no Microsoft-owned outbound IP. That is only safe
  # when something else provides egress, so it tracks the NAT gateway.
  default_outbound_access_enabled = !var.enable_nat_gateway

  # checkov:skip=CKV2_AZURE_31:The commit, edge, proxy and app subnets each have an NSG associated below; this graph check does not resolve the for_each. AzureBastionSubnet is genuinely without one, because Bastion requires a specific inbound rule set and an incorrect NSG breaks the service outright. See the TODO below.
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

# TODO(chris): NSG for AzureBastionSubnet. Bastion requires specific inbound
# rules (GatewayManager and AzureLoadBalancer on 443, the control plane ports)
# and an NSG missing any of them disables the service rather than degrading it.
# Worth building deliberately rather than copying, since getting it wrong is
# how people lock themselves out of their own management path.

# --- outbound egress ---------------------------------------------------------
# Off by default. See var.enable_nat_gateway for why this is a choice rather
# than simply the right answer.

resource "azurerm_public_ip" "nat" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "${var.name_prefix}-pip-nat"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.nat_gateway_zones
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  count                   = var.enable_nat_gateway ? 1 : 0
  name                    = "${var.name_prefix}-natgw"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = var.nat_gateway_zones
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count                = var.enable_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

# The Bastion subnet is deliberately excluded: Bastion manages its own outbound
# and Azure rejects a NAT gateway association on AzureBastionSubnet.
resource "azurerm_subnet_nat_gateway_association" "this" {
  for_each       = var.enable_nat_gateway ? toset(["commit", "edge", "proxy", "app"]) : toset([])
  subnet_id      = azurerm_subnet.this[each.key].id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}
