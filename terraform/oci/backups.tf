resource "oci_core_volume_backup_policy" "data" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.resource_prefix}-data-daily"
  freeform_tags  = merge(local.common_tags, { role = "recovery" })

  schedules {
    backup_type       = "INCREMENTAL"
    hour_of_day       = 20
    period            = "ONE_DAY"
    retention_seconds = 216000
    time_zone         = "UTC"
  }
}

resource "oci_core_volume_backup_policy" "critical_boot" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.resource_prefix}-critical-boot-weekly"
  freeform_tags  = merge(local.common_tags, { role = "recovery" })

  schedules {
    backup_type       = "INCREMENTAL"
    day_of_week       = "SUNDAY"
    hour_of_day       = 21
    period            = "ONE_WEEK"
    retention_seconds = 518400
    time_zone         = "UTC"
  }
}

resource "oci_core_volume_backup_policy_assignment" "data" {
  asset_id  = oci_core_volume.data.id
  policy_id = oci_core_volume_backup_policy.data.id
}

resource "oci_core_volume_backup_policy_assignment" "critical_boot" {
  for_each = local.protected_boot_nodes

  asset_id  = one(data.oci_core_boot_volume_attachments.protected[each.key].boot_volume_attachments).boot_volume_id
  policy_id = oci_core_volume_backup_policy.critical_boot.id
}
