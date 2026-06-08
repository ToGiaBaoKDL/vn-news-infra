resource "cloudflare_zero_trust_tunnel_cloudflared" "role" {
  for_each = local.tunnel_roles

  account_id = var.cloudflare_account_id
  name       = each.value.name
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "role" {
  for_each = cloudflare_zero_trust_tunnel_cloudflared.role

  account_id = var.cloudflare_account_id
  tunnel_id  = each.value.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "role" {
  for_each = local.tunnel_roles

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.role[each.key].id
  config = {
    ingress = concat(
      [
        for name, service in local.services_by_role[each.key] : {
          hostname = local.ui_hostnames[name]
          service  = service.origin
        }
      ],
      [
        {
          service = "http_status:404"
        }
      ]
    )
  }
}

resource "cloudflare_dns_record" "ui" {
  for_each = local.ui_services

  zone_id = var.cloudflare_zone_id
  name    = local.ui_hostnames[each.key]
  content = "${cloudflare_zero_trust_tunnel_cloudflared.role[each.value.role].id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}
