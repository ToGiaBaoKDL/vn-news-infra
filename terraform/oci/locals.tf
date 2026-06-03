locals {
  environment     = "prod"
  project         = "vn-news"
  resource_prefix = "tgb-vn-news"

  vcn_cidr           = "10.0.0.0/16"
  public_subnet_cidr = "10.0.10.0/24"

  availability_domain = var.availability_domain == "auto" ? data.oci_identity_availability_domains.home.availability_domains[0].name : var.availability_domain

  shape                   = "VM.Standard.A1.Flex"
  boot_volume_size_gb     = 50
  boot_volume_vpus_per_gb = 10
  data_volume_size_gb     = 50
  data_volume_vpus_per_gb = 10

  common_tags = {
    project     = local.project
    environment = local.environment
    managed-by  = "terraform"
  }

  roles = {
    data = {
      node_name = "tgb-data-1"
      nsg_name  = "${local.resource_prefix}-data-nsg"
    }
    control = {
      node_name = "tgb-control-1"
      nsg_name  = "${local.resource_prefix}-control-nsg"
    }
    processing = {
      node_name = "tgb-processing-1"
      nsg_name  = "${local.resource_prefix}-processing-nsg"
    }
  }

  nodes = {
    tgb-data-1 = {
      role           = "data"
      hostname_label = "data1"
      ocpus          = 1
      memory_gb      = 6
    }
    tgb-control-1 = {
      role           = "control"
      hostname_label = "control1"
      ocpus          = 1
      memory_gb      = 6
    }
    tgb-processing-1 = {
      role           = "processing"
      hostname_label = "processing1"
      ocpus          = 2
      memory_gb      = 12
    }
  }

  data_service_ports = {
    redpanda_kafka           = 19092
    redpanda_schema_registry = 18081
    seaweedfs_s3             = 8333
  }

  runtime_secret_ocids_by_role = {
    for role in keys(local.roles) : role => lookup(var.runtime_secret_ocids, role, [])
  }

  runtime_secret_roles = {
    for role, secret_ocids in local.runtime_secret_ocids_by_role : role => secret_ocids
    if length(secret_ocids) > 0
  }

  guardrails = {
    instance_count              = length(local.nodes)
    total_ocpus                 = local.nodes["tgb-data-1"].ocpus + local.nodes["tgb-control-1"].ocpus + local.nodes["tgb-processing-1"].ocpus
    total_memory_gb             = local.nodes["tgb-data-1"].memory_gb + local.nodes["tgb-control-1"].memory_gb + local.nodes["tgb-processing-1"].memory_gb
    boot_volume_gb              = local.boot_volume_size_gb * length(local.nodes)
    attached_block_volume_gb    = local.data_volume_size_gb
    total_live_block_storage_gb = (local.boot_volume_size_gb * length(local.nodes)) + local.data_volume_size_gb
    vault_count                 = 1
    key_count                   = 1
    vcn_count                   = 1
    recovery_bucket_count       = 1
  }
}
