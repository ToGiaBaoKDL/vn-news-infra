#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/resource_manager_common.sh"

if [[ -z "${OCI_RM_STACK_OCID:-}" ]]; then
  echo "Missing required environment variable: OCI_RM_STACK_OCID" >&2
  exit 1
fi

require_resource_manager_env

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

variables_json="$tmp_dir/resource-manager-variables.json"
compartment_file="$tmp_dir/compartment_ocid"
render_resource_manager_variables "$variables_json" "$compartment_file"

variables_payload="$(<"$variables_json")"

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
  --freeform-tags '{"project":"vn-news","environment":"prod","managed-by":"oci-resource-manager"}' \
  --force
