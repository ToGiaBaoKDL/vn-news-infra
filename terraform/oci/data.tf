data "oci_identity_availability_domains" "home" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_boot_volume_attachments" "control" {
  for_each = local.control_boot_nodes

  availability_domain = local.availability_domain
  compartment_id      = var.compartment_ocid
  instance_id         = oci_core_instance.node[each.key].id
}
