data "oci_identity_availability_domains" "home" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_boot_volume_attachments" "protected" {
  for_each = local.protected_boot_nodes

  availability_domain = local.availability_domain
  compartment_id      = var.compartment_ocid
  instance_id         = oci_core_instance.node[each.key].id
}
