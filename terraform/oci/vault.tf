resource "oci_kms_vault" "runtime" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.resource_prefix}-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = merge(local.common_tags, { role = "secrets" })
}

resource "oci_kms_key" "runtime" {
  compartment_id      = var.compartment_ocid
  display_name        = "${local.resource_prefix}-runtime-key"
  management_endpoint = oci_kms_vault.runtime.management_endpoint
  protection_mode     = "SOFTWARE"
  freeform_tags       = merge(local.common_tags, { role = "secrets" })

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}
