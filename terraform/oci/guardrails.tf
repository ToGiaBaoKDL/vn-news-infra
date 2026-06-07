resource "terraform_data" "always_free_guardrails" {
  input = local.guardrails

  lifecycle {
    precondition {
      condition     = local.guardrails.instance_count == 3
      error_message = "Always Free guardrail failed: exactly 3 A1 instances are allowed."
    }

    precondition {
      condition     = local.guardrails.total_ocpus == 4
      error_message = "Always Free guardrail failed: total OCPUs must be 4."
    }

    precondition {
      condition     = local.guardrails.total_memory_gb == 24
      error_message = "Always Free guardrail failed: total memory must be 24 GB."
    }

    precondition {
      condition     = local.guardrails.boot_volume_gb == 150
      error_message = "Always Free guardrail failed: boot volumes must total 150 GB."
    }

    precondition {
      condition     = local.guardrails.attached_block_volume_gb == 50
      error_message = "Always Free guardrail failed: attached block storage must be 50 GB."
    }

    precondition {
      condition     = local.guardrails.total_live_block_storage_gb == 200
      error_message = "Always Free guardrail failed: live boot and block storage must total 200 GB."
    }

    precondition {
      condition     = local.guardrails.retained_backup_slots == 5
      error_message = "Always Free guardrail failed: retained backup allocation must total 5 slots."
    }

    precondition {
      condition     = local.guardrails.recovery_bucket_limit_gib == 20
      error_message = "Always Free guardrail failed: recovery bucket capacity guardrail must remain 20 GiB."
    }
  }
}
