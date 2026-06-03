#!/usr/bin/env bash

set -euo pipefail

role="${1:-}"
vcn_cidr="${VN_NEWS_VCN_CIDR:-10.0.0.0/16}"
deploy_user="${SUDO_USER:-ubuntu}"

log() {
  printf '[vn-news-bootstrap] %s\n' "$*"
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root, for example: sudo $0 <data|control|processing>" >&2
    exit 1
  fi
}

require_role() {
  case "$role" in
    data | control | processing) ;;
    *)
      echo "Usage: sudo $0 <data|control|processing>" >&2
      exit 1
      ;;
  esac
}

ensure_dir() {
  local path="$1"
  local mode="$2"
  local owner="$3"

  install -d -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$path"
}

install_base_packages() {
  log "Installing base packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    ca-certificates \
    curl \
    git \
    gnupg \
    lsb-release \
    openssh-server \
    ufw \
    util-linux \
    xfsprogs
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker already installed"
    return
  fi

  log "Installing Docker Engine"
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "Unsupported OS for this bootstrap script: ${ID:-unknown}" >&2
    exit 1
  fi

  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable
EOF

  apt-get update
  apt-get install -y \
    containerd.io \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin

  install -d -m 0755 /etc/docker
  cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "local"
}
EOF

  systemctl enable docker
  systemctl restart docker
}

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

  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    systemctl reload ssh
  else
    systemctl reload sshd
  fi
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

configure_runtime_dirs() {
  log "Creating runtime directories"
  ensure_dir /etc/vn-news 0750 root:vn-news
  ensure_dir /etc/vn-news/env 0750 root:vn-news
  ensure_dir /run/vn-news 0700 root:root
  ensure_dir /run/vn-news/secrets 0700 root:root

  local role_env="/etc/vn-news/env/${role}.env"
  if [[ ! -f "$role_env" ]]; then
    touch "$role_env"
  fi
  chown root:vn-news "$role_env"
  chmod 0640 "$role_env"
}

data_device() {
  if [[ -n "${VN_NEWS_DATA_DEVICE:-}" ]]; then
    printf '%s\n' "$VN_NEWS_DATA_DEVICE"
    return
  fi

  if [[ -b /dev/oracleoci/oraclevdb ]]; then
    printf '%s\n' /dev/oracleoci/oraclevdb
    return
  fi

  if [[ -b /dev/sdb ]]; then
    printf '%s\n' /dev/sdb
    return
  fi

  return 1
}

assert_not_root_disk() {
  local device="$1"
  local root_source root_parent device_real device_base

  root_source="$(findmnt -n -o SOURCE /)"
  root_parent="$(lsblk -ndo PKNAME "$root_source" 2>/dev/null || true)"
  device_real="$(readlink -f "$device")"
  device_base="$(basename "$device_real")"

  if [[ -n "$root_parent" && "$device_base" == "$root_parent" ]]; then
    echo "Refusing to use root disk as data volume: $device" >&2
    exit 1
  fi
}

mount_data_volume() {
  local mount_point="/srv/vn-news-data"
  local device uuid

  log "Configuring data volume"
  ensure_dir "$mount_point" 0775 root:vn-news

  if findmnt -rn "$mount_point" >/dev/null 2>&1; then
    log "Data volume already mounted at $mount_point"
  else
    if ! device="$(data_device)"; then
      echo "Data volume not found. Set VN_NEWS_DATA_DEVICE=/dev/<device> and rerun." >&2
      exit 1
    fi

    assert_not_root_disk "$device"

    if ! blkid "$device" >/dev/null 2>&1; then
      log "Formatting $device as xfs"
      mkfs.xfs -f "$device"
    fi

    uuid="$(blkid -s UUID -o value "$device")"
    if [[ -z "$uuid" ]]; then
      echo "Could not read filesystem UUID from $device" >&2
      exit 1
    fi

    if ! grep -q "UUID=${uuid}[[:space:]]" /etc/fstab; then
      printf 'UUID=%s %s xfs defaults,nofail,x-systemd.device-timeout=30 0 2\n' "$uuid" "$mount_point" >>/etc/fstab
    fi

    mount "$mount_point"
  fi

  ensure_dir "$mount_point/redpanda" 0775 root:vn-news
  ensure_dir "$mount_point/seaweedfs" 0775 root:vn-news
  ensure_dir "$mount_point/polaris-postgres" 0775 root:vn-news
}

configure_role_dirs() {
  case "$role" in
    data)
      mount_data_volume
      ;;
    control)
      ensure_dir /srv/vn-news-control 0775 root:vn-news
      ensure_dir /srv/vn-news-control/airflow-db 0775 root:vn-news
      ensure_dir /srv/vn-news-control/airflow-logs 0775 root:vn-news
      ensure_dir /srv/vn-news-control/prometheus 0775 root:vn-news
      ;;
    processing)
      ensure_dir /srv/vn-news-processing 0775 root:vn-news
      ;;
  esac
}

main() {
  require_role
  require_root
  install_base_packages
  install_docker
  configure_users
  configure_ssh
  configure_firewall
  configure_runtime_dirs
  configure_role_dirs
  log "Bootstrap complete for role: $role"
}

main "$@"
