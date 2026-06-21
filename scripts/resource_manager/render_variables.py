from __future__ import annotations

import argparse
import json
from pathlib import Path

from scripts.secrets.terraform_vars import load_tfvars

REQUIRED_VARIABLES = (
    "arm64_ubuntu_image_ocid",
    "compartment_ocid",
    "region",
    "ssh_authorized_key",
    "ssh_ingress_cidr",
    "tenancy_ocid",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render OCI Resource Manager variables from JSON Terraform variables."
    )
    parser.add_argument("--tfvars", default="terraform/oci/terraform.tfvars.json")
    parser.add_argument("--variables-output", required=True)
    parser.add_argument("--compartment-output", required=True)
    return parser.parse_args()


def render_variables(tfvars_path: Path) -> dict[str, str]:
    payload = load_tfvars(tfvars_path)
    missing = [name for name in REQUIRED_VARIABLES if not payload.get(name)]
    if missing:
        raise SystemExit(f"Missing required Terraform variables in {tfvars_path}: {missing}")
    payload.setdefault("availability_domain", "auto")
    payload.setdefault("alarm_notification_email", "")
    payload.setdefault("runtime_secret_ocids", {})
    return {
        name: json.dumps(value, separators=(",", ":"))
        if isinstance(value, (dict, list))
        else str(value)
        for name, value in payload.items()
    }


def main() -> int:
    args = parse_args()
    tfvars_path = Path(args.tfvars)
    variables = render_variables(tfvars_path)
    variables_output = Path(args.variables_output)
    compartment_output = Path(args.compartment_output)

    variables_output.write_text(
        json.dumps(variables, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    compartment_output.write_text(variables["compartment_ocid"], encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
