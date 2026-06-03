#!/usr/bin/env bash
set -Eeuo pipefail

stack_name="${OCI_STACK_DISPLAY_NAME:-tgb-vn-news-prod}"
repo_url="${VN_NEWS_INFRA_REPO_URL:-https://github.com/ToGiaBaoKDL/vn-news-infra.git}"
repo_branch="${VN_NEWS_INFRA_BRANCH:-main}"
working_dir="${VN_NEWS_TERRAFORM_WORKING_DIR:-terraform/oci}"
terraform_version="${OCI_TERRAFORM_VERSION:-1.5.x}"
ssh_key_file="${OCI_SSH_AUTHORIZED_KEY_FILE:-$HOME/.ssh/vn_news_oracle_ed25519.pub}"
ssh_ingress_cidr="${OCI_SSH_INGRESS_CIDR:-0.0.0.0/0}"
oci_bin="${OCI_BIN:-oci}"

required_vars=(
  OCI_COMPARTMENT_OCID
  OCI_TENANCY_OCID
  OCI_REGION
  OCI_AVAILABILITY_DOMAIN
  OCI_ARM64_UBUNTU_IMAGE_OCID
  OCI_RM_CONFIG_SOURCE_PROVIDER_OCID
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required environment variable: ${var_name}" >&2
    exit 1
  fi
done

if ! command -v "$oci_bin" >/dev/null 2>&1; then
  echo "OCI CLI not found. Set OCI_BIN=/path/to/oci or add oci to PATH." >&2
  exit 1
fi

if [[ ! -f "$ssh_key_file" ]]; then
  echo "SSH public key file not found: ${ssh_key_file}" >&2
  exit 1
fi

ssh_authorized_key="$(<"$ssh_key_file")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

variables_json="$tmp_dir/resource-manager-variables.json"
python3 - "$variables_json" <<PY
from __future__ import annotations

import json
import os
import sys

variables = {
    "compartment_ocid": os.environ["OCI_COMPARTMENT_OCID"],
    "tenancy_ocid": os.environ["OCI_TENANCY_OCID"],
    "region": os.environ["OCI_REGION"],
    "availability_domain": os.environ["OCI_AVAILABILITY_DOMAIN"],
    "arm64_ubuntu_image_ocid": os.environ["OCI_ARM64_UBUNTU_IMAGE_OCID"],
    "ssh_authorized_key": ${ssh_authorized_key@Q},
    "ssh_ingress_cidr": ${ssh_ingress_cidr@Q},
    "runtime_secret_ocids": {},
}

with open(sys.argv[1], "w", encoding="utf-8") as file:
    json.dump(variables, file, indent=2)
    file.write("\\n")
PY

echo "Creating Resource Manager stack: ${stack_name}"
echo "Repository: ${repo_url}"
echo "Branch: ${repo_branch}"
echo "Working directory: ${working_dir}"

"$oci_bin" resource-manager stack create-from-git-provider \
  --compartment-id "$OCI_COMPARTMENT_OCID" \
  --display-name "$stack_name" \
  --description "VN News production Terraform stack." \
  --config-source-configuration-source-provider-id "$OCI_RM_CONFIG_SOURCE_PROVIDER_OCID" \
  --config-source-repository-url "$repo_url" \
  --config-source-branch-name "$repo_branch" \
  --config-source-working-directory "$working_dir" \
  --terraform-version "$terraform_version" \
  --variables "file://${variables_json}" \
  --freeform-tags '{"project":"vn-news","environment":"prod","managed-by":"oci-resource-manager"}'
