#!/usr/bin/env bash
set -euo pipefail

role="${1:-}"
vcn_cidr="${VN_NEWS_VCN_CIDR:-10.0.0.0/16}"
deploy_user="${SUDO_USER:-ubuntu}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$script_dir/lib/common.sh"
source "$script_dir/lib/packages.sh"
source "$script_dir/lib/security.sh"
source "$script_dir/lib/runtime.sh"
source "$script_dir/lib/volumes.sh"
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
  install_uv
  install_docker
  configure_users
  configure_ssh
  configure_firewall
  configure_runtime_dirs
  configure_role_dirs
  log "Bootstrap complete for role: $role"
}

main "$@"
