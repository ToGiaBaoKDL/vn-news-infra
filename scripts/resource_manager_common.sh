#!/usr/bin/env bash

stack_name="${OCI_STACK_DISPLAY_NAME:-tgb-vn-news-prod}"
repo_url="${VN_NEWS_INFRA_REPO_URL:-https://github.com/ToGiaBaoKDL/vn-news-infra.git}"
repo_branch="${VN_NEWS_INFRA_BRANCH:-main}"
working_dir="${VN_NEWS_TERRAFORM_WORKING_DIR:-terraform/oci}"
terraform_version="${OCI_TERRAFORM_VERSION:-1.5.x}"
tfvars_file="${VN_NEWS_TFVARS_FILE:-terraform/oci/terraform.tfvars}"
oci_bin="${OCI_BIN:-oci}"

require_resource_manager_env() {
  if [[ -z "${OCI_RM_CONFIG_SOURCE_PROVIDER_OCID:-}" ]]; then
    echo "Missing required environment variable: OCI_RM_CONFIG_SOURCE_PROVIDER_OCID" >&2
    exit 1
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

render_resource_manager_variables() {
  local variables_json="$1"
  local compartment_file="$2"

  python3 - "$tfvars_file" "$variables_json" "$compartment_file" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


tfvars_path = Path(sys.argv[1])
variables_path = Path(sys.argv[2])
compartment_path = Path(sys.argv[3])

text = tfvars_path.read_text(encoding="utf-8")


def read_string(name: str, *, required: bool = True, default: str | None = None) -> str | None:
    match = re.search(rf'^\s*{re.escape(name)}\s*=\s*"([^"]*)"\s*$', text, re.MULTILINE)
    if match:
        return match.group(1)
    if required:
        raise SystemExit(f"Missing required Terraform variable in {tfvars_path}: {name}")
    return default


def read_secret_map() -> dict[str, list[str]]:
    match = re.search(r"^\s*runtime_secret_ocids\s*=\s*\{(?P<body>.*?)^\s*\}", text, re.MULTILINE | re.DOTALL)
    if not match:
        return {}

    secrets: dict[str, list[str]] = {}
    body = match.group("body")
    for role in ("data", "control", "processing"):
        role_match = re.search(rf"^\s*{role}\s*=\s*\[(?P<items>.*?)\]\s*$", body, re.MULTILINE | re.DOTALL)
        if not role_match:
            continue
        secrets[role] = re.findall(r'"([^"]+)"', role_match.group("items"))
    return {role: ocids for role, ocids in secrets.items() if ocids}


variables = {
    "compartment_ocid": read_string("compartment_ocid"),
    "tenancy_ocid": read_string("tenancy_ocid"),
    "region": read_string("region"),
    "availability_domain": read_string("availability_domain"),
    "arm64_ubuntu_image_ocid": read_string("arm64_ubuntu_image_ocid"),
    "ssh_authorized_key": read_string("ssh_authorized_key"),
    "ssh_ingress_cidr": read_string("ssh_ingress_cidr", required=False, default="0.0.0.0/0"),
    "runtime_secret_ocids": json.dumps(read_secret_map()),
}

with variables_path.open("w", encoding="utf-8") as file:
    json.dump(variables, file, separators=(",", ":"))
    file.write("\n")

compartment_path.write_text(variables["compartment_ocid"], encoding="utf-8")
PY
}

print_stack_context() {
  local action="$1"

  echo "${action} Resource Manager stack: ${stack_name}"
  echo "Repository: ${repo_url}"
  echo "Branch: ${repo_branch}"
  echo "Working directory: ${working_dir}"
  echo "Variables file: ${tfvars_file}"
}
