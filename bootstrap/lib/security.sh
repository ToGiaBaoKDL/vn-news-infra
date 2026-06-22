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
  local cidr entry location
  local -a ssh_entries
  local managed_ssh_cidrs_file="/etc/vn-news/ssh-ingress-cidrs"

  log "Configuring UFW"
  ufw default deny incoming
  ufw default allow outgoing

  if [[ -f "$managed_ssh_cidrs_file" ]]; then
    while IFS='=' read -r _ cidr; do
      [[ -n "$cidr" ]] || continue
      if ufw status | grep -Fq "$cidr"; then
        ufw --force delete allow from "$cidr" to any port 22 proto tcp
      fi
    done <"$managed_ssh_cidrs_file"
  fi
  install -d -m 0755 /etc/vn-news
  : >"$managed_ssh_cidrs_file"
  read -r -a ssh_entries <<<"$ssh_ingress_cidrs"
  for entry in "${ssh_entries[@]}"; do
    if [[ "$entry" != *=* ]]; then
      echo "Invalid VN_NEWS_SSH_INGRESS_CIDRS entry: $entry" >&2
      exit 1
    fi
    location="${entry%%=*}"
    cidr="${entry#*=}"
    ufw allow from "$cidr" to any port 22 proto tcp comment "vn-news-ssh-$location"
    printf '%s=%s\n' "$location" "$cidr" >>"$managed_ssh_cidrs_file"
  done
  chmod 0644 "$managed_ssh_cidrs_file"

  if [[ "$role" == "data" ]]; then
    ufw allow from "$vcn_cidr" to any port 19092 proto tcp
    ufw allow from "$vcn_cidr" to any port 18081 proto tcp
    ufw allow from "$vcn_cidr" to any port 8333 proto tcp
    ufw allow from "$vcn_cidr" to any port 18181 proto tcp
  fi

  if [[ "$role" == "control" ]]; then
    ufw allow from "$vcn_cidr" to any port 17077:17079 proto tcp
    ufw allow from "$vcn_cidr" to any port 18080 proto tcp
  fi

  if [[ "$role" == "processing" ]]; then
    ufw allow from "$vcn_cidr" to any port 17078 proto tcp
  fi

  ufw --force enable
}
