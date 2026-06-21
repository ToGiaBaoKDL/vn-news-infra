#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:?usage: scripts/resource_manager/stack.sh create|update}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
local_resource_manager_env="${VN_NEWS_RESOURCE_MANAGER_ENV_FILE:-.resource-manager.env}"

# shellcheck source=scripts/lib/common.sh
source "$script_dir/../lib/common.sh"

load_optional_env_file "$local_resource_manager_env"

stack_name="${OCI_STACK_DISPLAY_NAME:-tgb-vn-news-prod}"
repo_url="${VN_NEWS_INFRA_REPO_URL:-https://github.com/ToGiaBaoKDL/vn-news-infra.git}"
repo_branch="${VN_NEWS_INFRA_BRANCH:-main}"
working_dir="${VN_NEWS_TERRAFORM_WORKING_DIR:-terraform/oci}"
terraform_version="${OCI_TERRAFORM_VERSION:-1.5.x}"
tfvars_file="${VN_NEWS_TFVARS_FILE:-terraform/oci/terraform.tfvars.json}"
oci_bin="${OCI_BIN:-oci}"

require_resource_manager_context() {
  require_env_var OCI_RM_CONFIG_SOURCE_PROVIDER_OCID
  if [[ "$action" == "update" ]]; then
    require_env_var OCI_RM_STACK_OCID
  fi
  require_command "$oci_bin" "OCI CLI not found. Set OCI_BIN=/path/to/oci or add oci to PATH."
  if [[ ! -f "$tfvars_file" ]]; then
    echo "Terraform variables file not found: ${tfvars_file}" >&2
    echo "Create it from terraform/oci/terraform.tfvars.json.example first." >&2
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

  (
    cd "$repo_root"
    python3 -m scripts.resource_manager.render_variables \
      --tfvars "$tfvars_file" \
      --variables-output "$variables_json" \
      --compartment-output "$compartment_file"
  )
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
