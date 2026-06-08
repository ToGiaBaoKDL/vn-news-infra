output "ui_hostnames" {
  value = local.ui_hostnames
}

output "tunnel_ids" {
  value = {
    for role, tunnel in cloudflare_zero_trust_tunnel_cloudflared.role : role => tunnel.id
  }
}

output "cloudflare_tunnel_tokens" {
  value = {
    for role, token in data.cloudflare_zero_trust_tunnel_cloudflared_token.role : role => token.token
  }
  sensitive = true
}
