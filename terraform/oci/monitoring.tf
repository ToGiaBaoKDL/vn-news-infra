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
  namespace                    = local.metric_namespace
  pending_duration             = "PT15M"
  query                        = "DataVolumeUtilization[15m]{resourceId = \"${oci_core_instance.node[local.roles["data"].node_name].id}\"}.max() > ${local.data_volume_alarm_percent}"
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
  namespace                    = local.metric_namespace
  pending_duration             = "PT15M"
  query                        = "DataVolumeUtilization[15m]{resourceId = \"${oci_core_instance.node[local.roles["data"].node_name].id}\"}.absent(45m)"
  repeat_notification_duration = "PT24H"
  resolution                   = "1m"
  severity                     = "CRITICAL"
  freeform_tags                = merge(local.common_tags, { role = "data" })
}

resource "oci_monitoring_alarm" "recovery_bucket_full" {
  alarm_summary                = "The recovery bucket is above ${local.recovery_bucket_alarm_percent}% of its storage budget."
  body                         = "Inspect all tenancy Object Storage usage and recovery lifecycle execution before exceeding the Always Free allowance."
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

resource "oci_monitoring_alarm" "pipeline_consumer_lag" {
  for_each = local.pipeline_consumer_groups

  alarm_summary                = "${each.key} consumer lag is above ${local.pipeline_lag_alarm_threshold} messages."
  body                         = "Check Redpanda, worker health, and recent DLQ records before the backlog grows."
  compartment_id               = var.compartment_ocid
  destinations                 = [oci_ons_notification_topic.operations.id]
  display_name                 = "${local.resource_prefix}-${each.key}-lag"
  is_enabled                   = true
  metric_compartment_id        = var.compartment_ocid
  namespace                    = local.metric_namespace
  pending_duration             = "PT15M"
  query                        = "ConsumerGroupLagTotal[5m]{consumerGroup = \"${each.key}\"}.max() > ${local.pipeline_lag_alarm_threshold}"
  repeat_notification_duration = "PT6H"
  resolution                   = "1m"
  severity                     = "CRITICAL"
  freeform_tags                = merge(local.common_tags, { role = "processing" })
}

resource "oci_monitoring_alarm" "pipeline_metrics_absent" {
  for_each = local.pipeline_consumer_groups

  alarm_summary                = "Pipeline metrics are absent for ${each.key}."
  body                         = "Check the pipeline-metrics container and processing node instance-principal metrics permission."
  compartment_id               = var.compartment_ocid
  destinations                 = [oci_ons_notification_topic.operations.id]
  display_name                 = "${local.resource_prefix}-${each.key}-metrics-absent"
  is_enabled                   = true
  metric_compartment_id        = var.compartment_ocid
  namespace                    = local.metric_namespace
  pending_duration             = "PT30M"
  query                        = "ConsumerGroupLagTotal[15m]{consumerGroup = \"${each.key}\"}.absent(30m)"
  repeat_notification_duration = "PT24H"
  resolution                   = "1m"
  severity                     = "CRITICAL"
  freeform_tags                = merge(local.common_tags, { role = "processing" })
}

resource "oci_monitoring_alarm" "pipeline_dlq_growth" {
  alarm_summary                = "VN News DLQ is receiving new records."
  body                         = "Inspect DLQ source, error class, and source logs. Reprocess only after the root cause is fixed."
  compartment_id               = var.compartment_ocid
  destinations                 = [oci_ons_notification_topic.operations.id]
  display_name                 = "${local.resource_prefix}-dlq-growth"
  is_enabled                   = true
  metric_compartment_id        = var.compartment_ocid
  namespace                    = local.metric_namespace
  pending_duration             = "PT15M"
  query                        = "DlqEventCount[15m].sum() > 0"
  repeat_notification_duration = "PT6H"
  resolution                   = "1m"
  severity                     = "CRITICAL"
  freeform_tags                = merge(local.common_tags, { role = "processing" })
}

resource "oci_monitoring_alarm" "source_extraction_failure" {
  alarm_summary                = "A source has extraction failures without successful extracted articles."
  body                         = "Review source selectors, fetched HTML, and article-extractor logs for the source dimension."
  compartment_id               = var.compartment_ocid
  destinations                 = [oci_ons_notification_topic.operations.id]
  display_name                 = "${local.resource_prefix}-source-extraction-failure"
  is_enabled                   = true
  metric_compartment_id        = var.compartment_ocid
  namespace                    = local.metric_namespace
  pending_duration             = "PT30M"
  query                        = "SourceExtractionFailure[15m].max() > 0"
  repeat_notification_duration = "PT6H"
  resolution                   = "1m"
  severity                     = "CRITICAL"
  freeform_tags                = merge(local.common_tags, { role = "processing" })
}
