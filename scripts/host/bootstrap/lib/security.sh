#!/usr/bin/env bash
# shellcheck disable=SC2154

configure_users() {
  log "Configuring users and groups"
  groupadd -f vn-news

  if ! id "$deploy_user" >/dev/null 2>&1; then
    echo "Deployment user does not exist: $deploy_user" >&2
    exit 1
  fi
  usermod -aG docker,vn-news "$deploy_user"
}

configure_ssh() {
  log "Hardening SSH"
  install -d -m 0755 /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/99-vn-news-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF

  sshd -t

  if systemctl list-unit-files ssh.service --no-legend >/dev/null 2>&1; then
    systemctl reload ssh.service || systemctl restart ssh.service
    return
  fi

  if systemctl list-unit-files sshd.service --no-legend >/dev/null 2>&1; then
    systemctl reload sshd.service || systemctl restart sshd.service
    return
  fi

  service ssh reload || service ssh restart
}

configure_firewall() {
  log "Configuring UFW"
  ufw default deny incoming
  ufw default allow outgoing
  configure_ssh_firewall_rules "$ssh_ingress_cidrs"
  configure_role_private_firewall_rules "$role" "$vcn_cidr"
  disable_rpcbind_listener
  ufw --force enable
}
