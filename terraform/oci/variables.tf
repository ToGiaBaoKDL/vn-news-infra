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
  description = "Full OCI availability domain name, or auto to use the first tenancy availability domain."
  type        = string
  default     = "auto"

  validation {
    condition     = var.availability_domain == "auto" || can(regex(":", var.availability_domain))
    error_message = "availability_domain must be auto or the full OCI availability domain name, for example hlHt:AP-SINGAPORE-1-AD-1."
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

variable "ssh_ingress_cidrs" {
  description = "IPv4 CIDRs allowed to SSH into nodes."
  type        = set(string)

  validation {
    condition = length(var.ssh_ingress_cidrs) > 0 && alltrue([
      for cidr in var.ssh_ingress_cidrs :
      can(cidrnetmask(cidr))
    ])
    error_message = "ssh_ingress_cidrs must contain valid IPv4 CIDRs."
  }
}

variable "runtime_secret_ocids" {
  description = "Named OCI Vault secret OCIDs by runtime role. Values are generated outside Terraform."
  type        = map(map(string))
  default     = {}

  validation {
    condition     = alltrue([for role in keys(var.runtime_secret_ocids) : contains(["data", "control", "processing"], role)])
    error_message = "runtime_secret_ocids keys must be data, control, or processing."
  }

  validation {
    condition = alltrue(flatten([
      for secrets in values(var.runtime_secret_ocids) : [
        for secret_ocid in values(secrets) : startswith(secret_ocid, "ocid1.vaultsecret.")
      ]
    ]))
    error_message = "runtime_secret_ocids values must be OCI Vault secret OCIDs."
  }
}

variable "alarm_notification_email" {
  description = "Optional email endpoint for OCI alarm notifications. OCI requires email confirmation."
  type        = string
  default     = ""

  validation {
    condition     = var.alarm_notification_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alarm_notification_email))
    error_message = "alarm_notification_email must be empty or a valid email address."
  }
}
