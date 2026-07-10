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

  recovery_bucket_budget_gib    = 20
  recovery_bucket_alarm_percent = 70
  recovery_bucket_alarm_bytes   = floor(local.recovery_bucket_budget_gib * 1024 * 1024 * 1024 * local.recovery_bucket_alarm_percent / 100)
  recovery_daily_retention_days = 14
  metric_namespace              = "vn_news"
  data_volume_alarm_percent     = 70
  object_storage_service        = "objectstorage-${var.region}"

  backup_schedules = {
    data = {
      backup_type       = "INCREMENTAL"
      hour_of_day       = 20
      period            = "ONE_DAY"
      period_seconds    = 86400
      retention_seconds = 216000
      time_zone         = "UTC"
    }
    control_boot = {
      backup_type       = "INCREMENTAL"
      day_of_week       = "SUNDAY"
      hour_of_day       = 21
      period            = "ONE_WEEK"
      period_seconds    = 604800
      retention_seconds = 691200
      time_zone         = "UTC"
    }
  }

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
      private_ip     = "10.0.10.16"
      ocpus          = 1
      memory_gb      = 6
    }
    tgb-control-1 = {
      role           = "control"
      hostname_label = "control1"
      private_ip     = "10.0.10.221"
      ocpus          = 1
      memory_gb      = 6
    }
    tgb-processing-1 = {
      role           = "processing"
      hostname_label = "processing1"
      private_ip     = "10.0.10.50"
      ocpus          = 2
      memory_gb      = 12
    }
  }

  control_boot_nodes = {
    for name, node in local.nodes : name => node
    if node.role == "control"
  }

  backup_slots = {
    data_volume         = ceil(local.backup_schedules.data.retention_seconds / local.backup_schedules.data.period_seconds)
    control_boot_volume = ceil(local.backup_schedules.control_boot.retention_seconds / local.backup_schedules.control_boot.period_seconds)
  }

  data_service_ports = {
    redpanda_kafka           = 19092
    redpanda_schema_registry = 18081
    seaweedfs_s3             = 8333
    polaris_catalog          = 18181
  }

  spark_ingress_rules = {
    control_cluster = {
      role = "control"
      min  = 17077
      max  = 17079
    }
    control_master_ui = {
      role = "control"
      min  = 18080
      max  = 18080
    }
    processing_worker = {
      role = "processing"
      min  = 17078
      max  = 17078
    }
    processing_worker_ui = {
      role = "processing"
      min  = 18081
      max  = 18081
    }
  }

  ssh_ingress_rules = merge([
    for cidr in var.ssh_ingress_cidrs : {
      for role in keys(local.roles) : "${role}:${replace(replace(cidr, "/", "_"), ".", "_")}" => {
        role = role
        cidr = cidr
      }
    }
  ]...)

  runtime_secret_ocids_by_role = {
    for role in keys(local.roles) : role => lookup(var.runtime_secret_ocids, role, {})
  }

  runtime_secret_roles = {
    for role, secrets in local.runtime_secret_ocids_by_role : role => values(secrets)
    if length(secrets) > 0
  }

  polaris_client_credentials_secret_ocid = lookup(
    local.runtime_secret_ocids_by_role["data"],
    "polaris_client_credentials",
    "",
  )

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
    retained_backup_slots       = sum(values(local.backup_slots))
    recovery_bucket_budget_gib  = local.recovery_bucket_budget_gib
  }
}
