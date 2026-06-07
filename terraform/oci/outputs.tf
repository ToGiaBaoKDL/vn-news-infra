output "nodes" {
  description = "Provisioned compute nodes by display name."
  value = {
    for name, instance in oci_core_instance.node : name => {
      id         = instance.id
      role       = local.nodes[name].role
      shape      = local.shape
      ocpus      = local.nodes[name].ocpus
      memory_gb  = local.nodes[name].memory_gb
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
    }
  }
}

output "network" {
  description = "Network resource identifiers."
  value = {
    vcn_id              = oci_core_vcn.main.id
    subnet_id           = oci_core_subnet.public.id
    internet_gateway_id = oci_core_internet_gateway.main.id
    route_table_id      = oci_core_route_table.public.id
    nsg_ids             = { for role, nsg in oci_core_network_security_group.role : role => nsg.id }
  }
}

output "data_volume" {
  description = "Data volume attached to tgb-data-1."
  value = {
    volume_id     = oci_core_volume.data.id
    attachment_id = oci_core_volume_attachment.data.id
    size_gb       = local.data_volume_size_gb
    mount_target  = "/srv/vn-news-data"
  }
}

output "recovery_bucket" {
  description = "Private recovery bucket."
  value = {
    namespace = data.oci_objectstorage_namespace.current.namespace
    name      = oci_objectstorage_bucket.recovery.name
  }
}

output "recovery_controls" {
  description = "Recovery retention, backup allocation, and alarm resources."
  value = {
    alarm_topic_id                = oci_ons_notification_topic.operations.id
    backup_slots                  = local.backup_slots
    data_backup_policy_id         = oci_core_volume_backup_policy.data.id
    critical_boot_policy_id       = oci_core_volume_backup_policy.critical_boot.id
    lifecycle_policy_id           = oci_objectstorage_object_lifecycle_policy.recovery.id
    recovery_bucket_alarm_bytes   = local.recovery_bucket_alarm_bytes
    recovery_bucket_limit_gib     = local.recovery_bucket_limit_gib
    notification_email_configured = var.alarm_notification_email != ""
  }
}

output "vault" {
  description = "Runtime secret Vault and key identifiers."
  value = {
    vault_id            = oci_kms_vault.runtime.id
    vault_name          = oci_kms_vault.runtime.display_name
    management_endpoint = oci_kms_vault.runtime.management_endpoint
    key_id              = oci_kms_key.runtime.id
  }
}

output "dynamic_groups" {
  description = "Role dynamic groups used for instance-principal secret access."
  value = {
    for role, group in oci_identity_dynamic_group.role : role => {
      id   = group.id
      name = group.name
    }
  }
}

output "always_free_guardrails" {
  description = "Expected Always Free resource totals."
  value       = terraform_data.always_free_guardrails.output
}
