#!/usr/bin/env bash
set -euo pipefail

role="${1:-}"
vcn_cidr="${VN_NEWS_VCN_CIDR:-10.0.0.0/16}"
ssh_ingress_cidrs="${VN_NEWS_SSH_INGRESS_CIDRS:?VN_NEWS_SSH_INGRESS_CIDRS is required}"
deploy_user="${SUDO_USER:-ubuntu}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bootstrap/lib/common.sh
source "$script_dir/lib/common.sh"
# shellcheck source=bootstrap/lib/packages.sh
source "$script_dir/lib/packages.sh"
# shellcheck source=scripts/host/firewall.sh
source "$script_dir/../scripts/host/firewall.sh"
# shellcheck source=bootstrap/lib/security.sh
source "$script_dir/lib/security.sh"
# shellcheck source=bootstrap/lib/runtime.sh
source "$script_dir/lib/runtime.sh"
# shellcheck source=bootstrap/lib/volumes.sh
source "$script_dir/lib/volumes.sh"
# shellcheck source=bootstrap/lib/roles.sh
source "$script_dir/lib/roles.sh"

configure_role_dirs() {
  case "$role" in
    data) configure_data_role ;;
    control) configure_control_role ;;
    processing) configure_processing_role ;;
  esac
}

main() {
  require_role
  require_root
  install_base_packages
  install_oci_cli
  if [[ "$role" == "data" ]]; then
    install_uv
  fi
  install_docker
  configure_users
  configure_ssh
  configure_firewall
  configure_runtime_dirs
  configure_role_dirs
  log "Bootstrap complete for role: $role"
}

main "$@"
