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
