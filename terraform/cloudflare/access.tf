resource "cloudflare_zero_trust_access_policy" "allow_owner" {
  account_id       = var.cloudflare_account_id
  name             = "tgb-vn-news-owner-access"
  decision         = "allow"
  session_duration = var.access_session_duration
  include = [
    {
      email = {
        email = var.allowed_email
      }
    }
  ]
}

resource "cloudflare_zero_trust_access_application" "ui" {
  for_each = local.ui_services

  account_id       = var.cloudflare_account_id
  type             = "self_hosted"
  name             = "tgb-vn-news-${each.key}"
  domain           = local.ui_hostnames[each.key]
  session_duration = var.access_session_duration
  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.allow_owner.id
      precedence = 1
    }
  ]
}
