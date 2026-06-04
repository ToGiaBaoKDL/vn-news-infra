#!/usr/bin/env bash

configure_users() {
  log "Configuring users and groups"
  groupadd -f vn-news

  if id "$deploy_user" >/dev/null 2>&1; then
    usermod -aG docker,vn-news "$deploy_user"
  fi
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
  ufw allow 22/tcp

  if [[ "$role" == "data" ]]; then
    ufw allow from "$vcn_cidr" to any port 19092 proto tcp
    ufw allow from "$vcn_cidr" to any port 18081 proto tcp
    ufw allow from "$vcn_cidr" to any port 8333 proto tcp
  fi

  ufw --force enable
}
