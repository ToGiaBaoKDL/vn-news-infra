variable "compartment_ocid" {
  description = "OCI compartment OCID that owns the project resources."
  type        = string

  validation {
    condition     = startswith(var.compartment_ocid, "ocid1.compartment.")
    error_message = "compartment_ocid must be an OCI compartment OCID."
  }
}

variable "tenancy_ocid" {
  description = "OCI tenancy OCID. Resource Manager prepopulates this value."
  type        = string

  validation {
    condition     = startswith(var.tenancy_ocid, "ocid1.tenancy.")
    error_message = "tenancy_ocid must be an OCI tenancy OCID."
  }
}

variable "region" {
  description = "OCI home region, for example ap-singapore-1."
  type        = string

  validation {
    condition     = length(trimspace(var.region)) > 0
    error_message = "region must not be empty."
  }
}

variable "availability_domain" {
  description = "Availability domain name used for all Always Free nodes and volumes."
  type        = string

  validation {
    condition     = length(trimspace(var.availability_domain)) > 0
    error_message = "availability_domain must not be empty."
  }
}

variable "arm64_ubuntu_image_ocid" {
  description = "ARM64 Ubuntu image OCID for VM.Standard.A1.Flex."
  type        = string

  validation {
    condition     = startswith(var.arm64_ubuntu_image_ocid, "ocid1.image.")
    error_message = "arm64_ubuntu_image_ocid must be an OCI image OCID."
  }
}

variable "ssh_authorized_key" {
  description = "Public SSH key installed on each node."
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(trimspace(var.ssh_authorized_key), "ssh-ed25519 ") || startswith(trimspace(var.ssh_authorized_key), "ssh-rsa ")
    error_message = "ssh_authorized_key must be an SSH public key."
  }
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to SSH into nodes. Use 0.0.0.0/0 for first rollout, then restrict."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.ssh_ingress_cidr))
    error_message = "ssh_ingress_cidr must be a valid IPv4 CIDR."
  }
}

variable "runtime_secret_ocids" {
  description = "Per-role OCI Vault secret OCIDs. Values are added after secrets are created outside Terraform."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for role in keys(var.runtime_secret_ocids) : contains(["data", "control", "processing"], role)])
    error_message = "runtime_secret_ocids keys must be data, control, or processing."
  }

  validation {
    condition = alltrue(flatten([
      for secret_ocids in values(var.runtime_secret_ocids) : [
        for secret_ocid in secret_ocids : startswith(secret_ocid, "ocid1.vaultsecret.")
      ]
    ]))
    error_message = "runtime_secret_ocids values must be OCI Vault secret OCIDs."
  }
}
