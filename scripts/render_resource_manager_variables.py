from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from runtime_secret_tfvars import read_runtime_secret_ocids


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render OCI Resource Manager variables from terraform.tfvars."
    )
    parser.add_argument("--tfvars", default="terraform/oci/terraform.tfvars")
    parser.add_argument("--variables-output", required=True)
    parser.add_argument("--compartment-output", required=True)
    return parser.parse_args()


def read_string(
    text: str,
    tfvars_path: Path,
    name: str,
    *,
    required: bool = True,
    default: str | None = None,
) -> str | None:
    match = re.search(rf'^\s*{re.escape(name)}\s*=\s*"([^"]*)"\s*$', text, re.MULTILINE)
    if match:
        return match.group(1)
    if required:
        raise SystemExit(
            f"Missing required Terraform variable in {tfvars_path}: {name}"
        )
    return default


def runtime_secret_map(tfvars_path: Path) -> dict[str, list[str]]:
    return {
        role: secret_ids
        for role, secret_ids in read_runtime_secret_ocids(tfvars_path).items()
        if secret_ids
    }


def render_variables(tfvars_path: Path) -> dict[str, str]:
    text = tfvars_path.read_text(encoding="utf-8")
    return {
        "compartment_ocid": read_string(text, tfvars_path, "compartment_ocid"),
        "tenancy_ocid": read_string(text, tfvars_path, "tenancy_ocid"),
        "region": read_string(text, tfvars_path, "region"),
        "availability_domain": read_string(
            text,
            tfvars_path,
            "availability_domain",
            required=False,
            default="auto",
        ),
        "arm64_ubuntu_image_ocid": read_string(
            text, tfvars_path, "arm64_ubuntu_image_ocid"
        ),
        "ssh_authorized_key": read_string(text, tfvars_path, "ssh_authorized_key"),
        "ssh_ingress_cidr": read_string(
            text,
            tfvars_path,
            "ssh_ingress_cidr",
            required=False,
            default="0.0.0.0/0",
        ),
        "alarm_notification_email": read_string(
            text,
            tfvars_path,
            "alarm_notification_email",
            required=False,
            default="",
        ),
        "runtime_secret_ocids": json.dumps(runtime_secret_map(tfvars_path)),
    }


def main() -> int:
    args = parse_args()
    tfvars_path = Path(args.tfvars)
    variables = render_variables(tfvars_path)
    variables_output = Path(args.variables_output)
    compartment_output = Path(args.compartment_output)

    with variables_output.open("w", encoding="utf-8") as file:
        json.dump(variables, file, separators=(",", ":"))
        file.write("\n")
    compartment_output.write_text(str(variables["compartment_ocid"]), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
