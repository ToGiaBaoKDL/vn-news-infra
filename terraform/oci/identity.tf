resource "oci_identity_dynamic_group" "role" {
  for_each = local.roles

  compartment_id = var.tenancy_ocid
  name           = "${local.resource_prefix}-${each.key}-dg"
  description    = "Instance principal group for ${each.value.node_name}."
  matching_rule  = "ANY {instance.id = '${oci_core_instance.node[each.value.node_name].id}'}"
  freeform_tags  = merge(local.common_tags, { role = each.key })
}

resource "oci_identity_policy" "runtime_secret_read" {
  for_each = local.runtime_secret_roles

  compartment_id = var.tenancy_ocid
  name           = "${local.resource_prefix}-${each.key}-secret-read"
  description    = "Allow ${each.key} node to read only its assigned runtime secret bundles."
  freeform_tags  = merge(local.common_tags, { role = each.key })

  statements = [
    for secret_ocid in each.value :
    "Allow dynamic-group ${oci_identity_dynamic_group.role[each.key].name} to read secret-bundles in compartment id ${var.compartment_ocid} where target.secret.id = '${secret_ocid}'"
  ]
}

resource "oci_identity_policy" "recovery_object_access" {
  for_each = toset(["data", "control"])

  compartment_id = var.tenancy_ocid
  name           = "${local.resource_prefix}-${each.key}-recovery-object-access"
  description    = "Allow ${each.key} node to manage compact recovery exports."
  freeform_tags  = merge(local.common_tags, { role = each.key })

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.role[each.key].name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name = '${oci_objectstorage_bucket.recovery.name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.role[each.key].name} to read buckets in compartment id ${var.compartment_ocid} where target.bucket.name = '${oci_objectstorage_bucket.recovery.name}'",
  ]
}

resource "oci_identity_policy" "object_lifecycle_service_access" {
  compartment_id = var.tenancy_ocid
  name           = "${local.resource_prefix}-object-lifecycle-service-access"
  description    = "Allow regional Object Storage lifecycle policies to manage recovery objects."
  freeform_tags  = merge(local.common_tags, { role = "recovery" })

  statements = [
    "Allow service ${local.object_storage_service} to manage object-family in compartment id ${var.compartment_ocid}",
  ]
}

resource "oci_identity_policy" "data_metric_publish" {
  compartment_id = var.tenancy_ocid
  name           = "${local.resource_prefix}-data-metric-publish"
  description    = "Allow the data node to publish mount-capacity metrics."
  freeform_tags  = merge(local.common_tags, { role = "data" })

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.role["data"].name} to use metrics in compartment id ${var.compartment_ocid}",
  ]
}
