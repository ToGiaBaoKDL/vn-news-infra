data "oci_objectstorage_namespace" "current" {
  compartment_id = var.tenancy_ocid
}

resource "oci_core_volume" "data" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "${local.resource_prefix}-data-volume-1"
  size_in_gbs         = local.data_volume_size_gb
  vpus_per_gb         = local.data_volume_vpus_per_gb
  freeform_tags       = merge(local.common_tags, { role = "data" })
}

resource "oci_core_volume_attachment" "data" {
  attachment_type                     = "paravirtualized"
  display_name                        = "${local.resource_prefix}-data-volume-1-attachment"
  instance_id                         = oci_core_instance.node[local.roles["data"].node_name].id
  volume_id                           = oci_core_volume.data.id
  is_pv_encryption_in_transit_enabled = true
  is_read_only                        = false
}

resource "oci_objectstorage_bucket" "recovery" {
  compartment_id        = var.compartment_ocid
  namespace             = data.oci_objectstorage_namespace.current.namespace
  name                  = "${local.resource_prefix}-recovery"
  access_type           = "NoPublicAccess"
  auto_tiering          = "Disabled"
  object_events_enabled = false
  storage_tier          = "Standard"
  versioning            = "Disabled"
  freeform_tags         = merge(local.common_tags, { role = "recovery" })
}
