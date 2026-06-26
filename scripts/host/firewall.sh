#!/usr/bin/env bash

ufw_delete_rule() {
  ufw --force delete "$@" >/dev/null 2>&1 || true
}

configure_ssh_firewall_rules() {
  local ssh_ingress_cidrs="$1"
  local cidr entry managed_entry
  local managed_ssh_cidrs_file="/etc/vn-news/ssh-ingress-cidrs"
  local -a ssh_entries

  [[ -n "$ssh_ingress_cidrs" ]] || return

  install -d -m 0755 /etc/vn-news
  if [[ -f "$managed_ssh_cidrs_file" ]]; then
    while IFS= read -r managed_entry; do
      if [[ "$managed_entry" == *=* ]]; then
        cidr="${managed_entry#*=}"
      else
        cidr="$managed_entry"
      fi
      [[ -n "$cidr" ]] || continue
      ufw_delete_rule allow from "$cidr" to any port 22 proto tcp
    done <"$managed_ssh_cidrs_file"
  fi

  ufw_delete_rule allow 22/tcp
  ufw_delete_rule allow OpenSSH

  : >"$managed_ssh_cidrs_file"
  read -r -a ssh_entries <<<"$ssh_ingress_cidrs"
  for entry in "${ssh_entries[@]}"; do
    if [[ "$entry" == *=* ]]; then
      cidr="${entry#*=}"
    else
      cidr="$entry"
    fi
    ufw allow from "$cidr" to any port 22 proto tcp comment "vn-news-ssh" >/dev/null
    printf '%s\n' "$cidr" >>"$managed_ssh_cidrs_file"
  done
  chmod 0644 "$managed_ssh_cidrs_file"
}

configure_role_private_firewall_rules() {
  local role="$1"
  local private_cidr="$2"
  local port
  local ports=()

  [[ -n "$private_cidr" ]] || return

  case "$role" in
    data)
      ports=(19092 18081 8333 18181)
      ;;
    control)
      ports=(17077:17079 18080)
      ;;
    processing)
      ports=(17078 18081)
      ;;
    *)
      echo "Unsupported firewall role: $role" >&2
      exit 2
      ;;
  esac

  for port in "${ports[@]}"; do
    ufw allow from "$private_cidr" to any port "$port" proto tcp >/dev/null
  done
}

disable_rpcbind_listener() {
  local unit

  if ! command -v systemctl >/dev/null 2>&1; then
    return
  fi

  for unit in rpcbind.socket rpcbind.service; do
    if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
      systemctl disable --now "$unit" >/dev/null 2>&1 || true
    fi
  done
}
