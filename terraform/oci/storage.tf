data "oci_objectstorage_namespace" "current" {
  compartment_id = var.tenancy_ocid
}

resource "oci_core_volume" "data" {
  availability_domain = local.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "${local.resource_prefix}-data-volume-1"
  size_in_gbs         = tostring(local.data_volume_size_gb)
  vpus_per_gb         = tostring(local.data_volume_vpus_per_gb)
  freeform_tags       = merge(local.common_tags, { role = "data" })
}

resource "oci_core_volume_attachment" "data" {
  attachment_type = "paravirtualized"
  display_name    = "${local.resource_prefix}-data-volume-1-attachment"
  instance_id     = oci_core_instance.node[local.roles["data"].node_name].id
  volume_id       = oci_core_volume.data.id
  is_read_only    = false
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

resource "oci_objectstorage_object_lifecycle_policy" "recovery" {
  bucket    = oci_objectstorage_bucket.recovery.name
  namespace = data.oci_objectstorage_namespace.current.namespace

  rules {
    action      = "DELETE"
    is_enabled  = true
    name        = "delete-daily-recovery-artifacts"
    target      = "objects"
    time_amount = local.recovery_daily_retention_days
    time_unit   = "DAYS"

    object_name_filter {
      inclusion_patterns = [
        "airflow-db/*",
        "config/*",
        "redpanda-metadata/*",
      ]
    }
  }

  rules {
    action      = "DELETE"
    is_enabled  = true
    name        = "delete-release-manifests"
    target      = "objects"
    time_amount = local.recovery_release_retention_days
    time_unit   = "DAYS"

    object_name_filter {
      inclusion_patterns = ["release-manifests/*"]
    }
  }

  rules {
    action      = "ABORT"
    is_enabled  = true
    name        = "abort-incomplete-uploads"
    target      = "multipart-uploads"
    time_amount = 1
    time_unit   = "DAYS"
  }
}
