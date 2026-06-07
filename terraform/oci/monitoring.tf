resource "oci_ons_notification_topic" "operations" {
  compartment_id = var.compartment_ocid
  name           = "${local.resource_prefix}-operations"
  description    = "VN News production capacity and health alarms."
  freeform_tags  = merge(local.common_tags, { role = "operations" })
}

resource "oci_ons_subscription" "operations_email" {
  count = var.alarm_notification_email == "" ? 0 : 1

  compartment_id = var.compartment_ocid
  endpoint       = var.alarm_notification_email
  protocol       = "EMAIL"
  topic_id       = oci_ons_notification_topic.operations.id
}

resource "oci_monitoring_alarm" "node_unresponsive" {
  for_each = local.nodes

  alarm_summary                = "${each.key} is unresponsive."
  body                         = "Check OCI infrastructure health, then verify the node operating system and network."
  compartment_id               = var.compartment_ocid
  destinations                 = [oci_ons_notification_topic.operations.id]
  display_name                 = "${each.key}-unresponsive"
  is_enabled                   = true
  metric_compartment_id        = var.compartment_ocid
  namespace                    = "oci_compute_instance_health"
  pending_duration             = "PT5M"
  query                        = "instance_accessibility_status[1m]{resourceId = \"${oci_core_instance.node[each.key].id}\"}.max() > 0"
  repeat_notification_duration = "PT24H"
  resolution                   = "1m"
  severity                     = "CRITICAL"
  freeform_tags                = merge(local.common_tags, { role = each.value.role })
}

resource "oci_monitoring_alarm" "data_volume_full" {
  alarm_summary                = "The VN News data volume is above ${local.data_volume_alarm_percent}% utilization."
  body                         = "Reduce retained data or move to paid storage before the data volume is exhausted."
  compartment_id               = var.compartment_ocid
  destinations                 = [oci_ons_notification_topic.operations.id]
  display_name                 = "${local.resource_prefix}-data-volume-full"
  is_enabled                   = true
  metric_compartment_id        = var.compartment_ocid
  namespace                    = "vn_news"
  pending_duration             = "PT15M"
  query                        = "DataVolumeUtilization[5m]{resourceId = \"${oci_core_instance.node[local.roles["data"].node_name].id}\"}.max() > ${local.data_volume_alarm_percent}"
  repeat_notification_duration = "PT24H"
  resolution                   = "1m"
  severity                     = "CRITICAL"
  freeform_tags                = merge(local.common_tags, { role = "data" })
}

resource "oci_monitoring_alarm" "data_volume_metric_absent" {
  alarm_summary                = "The VN News data-volume capacity metric is absent."
  body                         = "Check the vn-news-data-volume-metric timer and instance-principal monitoring permission."
  compartment_id               = var.compartment_ocid
  destinations                 = [oci_ons_notification_topic.operations.id]
  display_name                 = "${local.resource_prefix}-data-volume-metric-absent"
  is_enabled                   = true
  metric_compartment_id        = var.compartment_ocid
  namespace                    = "vn_news"
  pending_duration             = "PT15M"
  query                        = "DataVolumeUtilization[5m]{resourceId = \"${oci_core_instance.node[local.roles["data"].node_name].id}\"}.absent(30m)"
  repeat_notification_duration = "PT24H"
  resolution                   = "1m"
  severity                     = "CRITICAL"
  freeform_tags                = merge(local.common_tags, { role = "data" })
}

resource "oci_monitoring_alarm" "recovery_bucket_full" {
  alarm_summary                = "The recovery bucket is above ${local.recovery_bucket_alarm_percent}% of the Always Free allowance."
  body                         = "Inspect recovery exports and lifecycle execution before the bucket exceeds the 20 GiB allowance."
  compartment_id               = var.compartment_ocid
  destinations                 = [oci_ons_notification_topic.operations.id]
  display_name                 = "${local.resource_prefix}-recovery-bucket-full"
  is_enabled                   = true
  metric_compartment_id        = var.compartment_ocid
  namespace                    = "oci_objectstorage"
  pending_duration             = "PT1H"
  query                        = "StoredBytes[1h]{resourceDisplayName = \"${oci_objectstorage_bucket.recovery.name}\"}.sum() > ${local.recovery_bucket_alarm_bytes}"
  repeat_notification_duration = "PT24H"
  resolution                   = "1m"
  severity                     = "CRITICAL"
  freeform_tags                = merge(local.common_tags, { role = "recovery" })
}
