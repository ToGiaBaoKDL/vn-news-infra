variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the Zero Trust team."
  type        = string

  validation {
    condition     = length(trimspace(var.cloudflare_account_id)) > 0
    error_message = "cloudflare_account_id must not be empty."
  }
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the public domain."
  type        = string

  validation {
    condition     = length(trimspace(var.cloudflare_zone_id)) > 0
    error_message = "cloudflare_zone_id must not be empty."
  }
}

variable "domain" {
  description = "Public domain used for VN News UI hostnames."
  type        = string
  default     = "tgblab.io.vn"

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.domain))
    error_message = "domain must be a lowercase DNS name."
  }
}

variable "allowed_email" {
  description = "Email allowed to access protected VN News UI applications."
  type        = string
  default     = "baokdl2226@gmail.com"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.allowed_email))
    error_message = "allowed_email must be a valid email address."
  }
}

variable "access_session_duration" {
  description = "Cloudflare Access session duration for protected UI applications."
  type        = string
  default     = "8h"
}
