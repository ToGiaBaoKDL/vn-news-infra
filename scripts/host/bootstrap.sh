#!/usr/bin/env bash
set -euo pipefail

role="${1:-}"
deploy_user="${SUDO_USER:-ubuntu}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vcn_cidr=""
ssh_ingress_cidrs=""

# shellcheck source=scripts/lib/common.sh
source "$script_dir/../lib/common.sh"
# shellcheck source=scripts/host/bootstrap/lib/helpers.sh
source "$script_dir/bootstrap/lib/helpers.sh"
# shellcheck source=scripts/host/bootstrap/lib/packages.sh
source "$script_dir/bootstrap/lib/packages.sh"
# shellcheck source=scripts/lib/firewall.sh
source "$script_dir/../lib/firewall.sh"
# shellcheck source=scripts/host/bootstrap/lib/security.sh
source "$script_dir/bootstrap/lib/security.sh"
# shellcheck source=scripts/host/bootstrap/lib/runtime.sh
source "$script_dir/bootstrap/lib/runtime.sh"
# shellcheck source=scripts/host/bootstrap/lib/volumes.sh
source "$script_dir/bootstrap/lib/volumes.sh"
# shellcheck source=scripts/host/bootstrap/lib/roles.sh
source "$script_dir/bootstrap/lib/roles.sh"

configure_role_dirs() {
  case "$role" in
    data) configure_data_role ;;
    control) configure_control_role ;;
    processing) configure_processing_role ;;
  esac
}

main() {
  require_role "$role" data control processing
  require_root
  load_optional_env_file "$(role_env_path "$role")"
  vcn_cidr="${VN_NEWS_PRIVATE_INGRESS_CIDR:-10.0.0.0/16}"
  ssh_ingress_cidrs="${VN_NEWS_SSH_INGRESS_CIDRS:?configure $(role_env_path "$role")}"
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
