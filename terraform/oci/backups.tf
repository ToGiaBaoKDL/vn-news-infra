resource "oci_core_volume_backup_policy" "data" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.resource_prefix}-data-daily"
  freeform_tags  = merge(local.common_tags, { role = "recovery" })

  schedules {
    backup_type       = local.backup_schedules.data.backup_type
    hour_of_day       = local.backup_schedules.data.hour_of_day
    period            = local.backup_schedules.data.period
    retention_seconds = local.backup_schedules.data.retention_seconds
    time_zone         = local.backup_schedules.data.time_zone
  }
}

resource "oci_core_volume_backup_policy" "control_boot" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.resource_prefix}-control-boot-weekly"
  freeform_tags  = merge(local.common_tags, { role = "control" })

  schedules {
    backup_type       = local.backup_schedules.control_boot.backup_type
    day_of_week       = local.backup_schedules.control_boot.day_of_week
    hour_of_day       = local.backup_schedules.control_boot.hour_of_day
    period            = local.backup_schedules.control_boot.period
    retention_seconds = local.backup_schedules.control_boot.retention_seconds
    time_zone         = local.backup_schedules.control_boot.time_zone
  }
}

resource "oci_core_volume_backup_policy_assignment" "data" {
  asset_id  = oci_core_volume.data.id
  policy_id = oci_core_volume_backup_policy.data.id
}

resource "oci_core_volume_backup_policy_assignment" "control_boot" {
  for_each = local.control_boot_nodes

  asset_id  = one(data.oci_core_boot_volume_attachments.control[each.key].boot_volume_attachments).boot_volume_id
  policy_id = oci_core_volume_backup_policy.control_boot.id
}
