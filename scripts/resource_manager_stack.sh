#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:?usage: scripts/resource_manager_stack.sh create|update}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_resource_manager_env="${VN_NEWS_RESOURCE_MANAGER_ENV_FILE:-.resource-manager.env}"

if [[ -f "$local_resource_manager_env" ]]; then
  set -a
  source "$local_resource_manager_env"
  set +a
fi

stack_name="${OCI_STACK_DISPLAY_NAME:-tgb-vn-news-prod}"
repo_url="${VN_NEWS_INFRA_REPO_URL:-https://github.com/ToGiaBaoKDL/vn-news-infra.git}"
repo_branch="${VN_NEWS_INFRA_BRANCH:-main}"
working_dir="${VN_NEWS_TERRAFORM_WORKING_DIR:-terraform/oci}"
terraform_version="${OCI_TERRAFORM_VERSION:-1.5.x}"
tfvars_file="${VN_NEWS_TFVARS_FILE:-terraform/oci/terraform.tfvars}"
oci_bin="${OCI_BIN:-oci}"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

require_resource_manager_context() {
  require_env OCI_RM_CONFIG_SOURCE_PROVIDER_OCID
  if [[ "$action" == "update" ]]; then
    require_env OCI_RM_STACK_OCID
  fi
  if ! command -v "$oci_bin" >/dev/null 2>&1; then
    echo "OCI CLI not found. Set OCI_BIN=/path/to/oci or add oci to PATH." >&2
    exit 1
  fi
  if [[ ! -f "$tfvars_file" ]]; then
    echo "Terraform variables file not found: ${tfvars_file}" >&2
    echo "Create it from terraform/oci/terraform.tfvars.example first." >&2
    exit 1
  fi
}

print_stack_context() {
  local label="$1"

  echo "${label} Resource Manager stack: ${stack_name}"
  echo "Repository: ${repo_url}"
  echo "Branch: ${repo_branch}"
  echo "Working directory: ${working_dir}"
  echo "Variables file: ${tfvars_file}"
}

render_variables() {
  local variables_json="$1"
  local compartment_file="$2"

  python3 "$script_dir/render_resource_manager_variables.py" \
    --tfvars "$tfvars_file" \
    --variables-output "$variables_json" \
    --compartment-output "$compartment_file"
}

case "$action" in
  create | update) ;;
  *)
    echo "Unknown Resource Manager action: $action" >&2
    exit 2
    ;;
esac

require_resource_manager_context

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

variables_json="$tmp_dir/resource-manager-variables.json"
compartment_file="$tmp_dir/compartment_ocid"
render_variables "$variables_json" "$compartment_file"

variables_payload="$(<"$variables_json")"
tags='{"project":"vn-news","environment":"prod","managed-by":"oci-resource-manager"}'

if [[ "$action" == "create" ]]; then
  compartment_ocid="$(<"$compartment_file")"
  print_stack_context "Creating"
  "$oci_bin" resource-manager stack create-from-git-provider \
    --compartment-id "$compartment_ocid" \
    --display-name "$stack_name" \
    --description "VN News production Terraform stack." \
    --config-source-configuration-source-provider-id "$OCI_RM_CONFIG_SOURCE_PROVIDER_OCID" \
    --config-source-repository-url "$repo_url" \
    --config-source-branch-name "$repo_branch" \
    --config-source-working-directory "$working_dir" \
    --terraform-version "$terraform_version" \
    --variables "$variables_payload" \
    --freeform-tags "$tags"
else
  print_stack_context "Updating"
  "$oci_bin" resource-manager stack update-from-git-provider \
    --stack-id "$OCI_RM_STACK_OCID" \
    --display-name "$stack_name" \
    --description "VN News production Terraform stack." \
    --config-source-configuration-source-provider-id "$OCI_RM_CONFIG_SOURCE_PROVIDER_OCID" \
    --config-source-repository-url "$repo_url" \
    --config-source-branch-name "$repo_branch" \
    --config-source-working-directory "$working_dir" \
    --terraform-version "$terraform_version" \
    --variables "$variables_payload" \
    --freeform-tags "$tags" \
    --force
fi
