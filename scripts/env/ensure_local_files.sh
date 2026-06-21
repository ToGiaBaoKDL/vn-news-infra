#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$script_dir/../lib/common.sh"

ensure_from_example() {
  local example_path="$1"
  local target_path="$2"
  local file_mode="${3:-0600}"

  require_readable_file "$repo_root/$example_path" "Missing template: $example_path"
  if [[ -e "$repo_root/$target_path" ]]; then
    echo "exists: $target_path"
    return
  fi

  install -m "$file_mode" "$repo_root/$example_path" "$repo_root/$target_path"
  echo "created: $target_path"
}

ensure_oci_tfvars_json() {
  local legacy_path="terraform/oci/terraform.tfvars"
  local target_path="terraform/oci/terraform.tfvars.json"

  if [[ -e "$repo_root/$target_path" ]]; then
    echo "exists: $target_path"
    return
  fi
  if [[ -e "$repo_root/$legacy_path" ]]; then
    echo "skipped: $target_path (${legacy_path} exists; migrate values before replacing it)"
    return
  fi
  ensure_from_example terraform/oci/terraform.tfvars.json.example "$target_path"
}

ensure_from_example .resource-manager.env.example .resource-manager.env
ensure_from_example bootstrap/bootstrap.env.example bootstrap/bootstrap.env
ensure_oci_tfvars_json
ensure_from_example terraform/cloudflare/terraform.tfvars.example terraform/cloudflare/terraform.tfvars
echo "manual: create terraform/cloudflare/backend.hcl from terraform/cloudflare/backend.hcl.example only after choosing the remote state bucket"
