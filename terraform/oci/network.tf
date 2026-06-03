resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [local.vcn_cidr]
  display_name   = "${local.resource_prefix}-vcn"
  dns_label      = "tgbvnnews"
  freeform_tags  = merge(local.common_tags, { role = "network" })
}

resource "oci_core_default_security_list" "main" {
  manage_default_resource_id = oci_core_vcn.main.default_security_list_id
  display_name               = "${local.resource_prefix}-default-security-list"

  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    description      = "Allow outbound traffic."
  }

  freeform_tags = merge(local.common_tags, { role = "network" })
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  enabled        = true
  display_name   = "${local.resource_prefix}-internet-gateway"
  freeform_tags  = merge(local.common_tags, { role = "network" })
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.resource_prefix}-public-route-table"
  freeform_tags  = merge(local.common_tags, { role = "network" })

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
    description       = "Route public subnet egress through the internet gateway."
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = local.public_subnet_cidr
  display_name               = "${local.resource_prefix}-public-subnet"
  dns_label                  = "public"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_default_security_list.main.id]
  freeform_tags              = merge(local.common_tags, { role = "network" })
}

resource "oci_core_network_security_group" "role" {
  for_each = local.roles

  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = each.value.nsg_name
  freeform_tags  = merge(local.common_tags, { role = each.key })
}

resource "oci_core_network_security_group_security_rule" "role_egress_all" {
  for_each = local.roles

  network_security_group_id = oci_core_network_security_group.role[each.key].id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  stateless                 = false
  description               = "Allow outbound traffic from ${each.key} node."
}

resource "oci_core_network_security_group_security_rule" "role_ssh" {
  for_each = local.roles

  network_security_group_id = oci_core_network_security_group.role[each.key].id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.ssh_ingress_cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false
  description               = "Allow SSH to ${each.key} node."

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "data_services" {
  for_each = local.data_service_ports

  network_security_group_id = oci_core_network_security_group.role["data"].id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = local.vcn_cidr
  source_type               = "CIDR_BLOCK"
  stateless                 = false
  description               = "Allow ${each.key} from the VCN."

  tcp_options {
    destination_port_range {
      min = each.value
      max = each.value
    }
  }
}
