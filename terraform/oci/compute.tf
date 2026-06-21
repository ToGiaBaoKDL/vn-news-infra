resource "oci_core_instance" "node" {
  for_each = local.nodes

  availability_domain = local.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = each.key
  shape               = local.shape
  freeform_tags       = merge(local.common_tags, { role = each.value.role })

  shape_config {
    ocpus         = each.value.ocpus
    memory_in_gbs = each.value.memory_gb
  }

  create_vnic_details {
    assign_public_ip = "true"
    display_name     = "${each.key}-primary-vnic"
    hostname_label   = each.value.hostname_label
    private_ip       = each.value.private_ip
    nsg_ids          = [oci_core_network_security_group.role[each.value.role].id]
    subnet_id        = oci_core_subnet.public.id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_authorized_key
  }

  source_details {
    source_id               = var.arm64_ubuntu_image_ocid
    source_type             = "image"
    boot_volume_size_in_gbs = tostring(local.boot_volume_size_gb)
    boot_volume_vpus_per_gb = tostring(local.boot_volume_vpus_per_gb)
  }

  preserve_boot_volume = false
}
