from __future__ import annotations

import argparse
import json
from pathlib import Path

from scripts.secrets.catalog import SECRET_NAMES as RUNTIME_SECRET_NAMES
from scripts.secrets.oci import (
    create_secret,
    current_secret_content,
    list_existing_secrets,
    run_json,
    update_secret_content,
)
from scripts.secrets.terraform_vars import merge_runtime_secret_ocids

SECRET_KEYS = {
    "control": "cloudflare_control_tunnel_token",
    "data": "cloudflare_data_tunnel_token",
}
SECRET_NAMES = {role: RUNTIME_SECRET_NAMES[key] for role, key in SECRET_KEYS.items()}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync Cloudflare tunnel tokens from Terraform output into OCI Vault."
    )
    parser.add_argument("--compartment-id", required=True)
    parser.add_argument("--vault-id", required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--cloudflare-terraform-dir", default="terraform/cloudflare")
    parser.add_argument("--cloudflare-state-file")
    parser.add_argument("--oci-tfvars", default="terraform/oci/terraform.tfvars.json")
    parser.add_argument("--oci-bin", default="oci")
    parser.add_argument("--terraform-bin", default="terraform")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def tunnel_tokens_from_output(payload: dict) -> dict[str, str]:
    try:
        tokens = payload["cloudflare_tunnel_tokens"]["value"]
    except KeyError as exc:
        raise SystemExit("Missing cloudflare_tunnel_tokens Terraform output.") from exc
    missing = sorted(set(SECRET_NAMES) - set(tokens))
    if missing:
        raise SystemExit(f"Missing tunnel tokens for roles: {missing}")
    return {role: str(tokens[role]) for role in SECRET_NAMES}


def terraform_outputs(
    terraform_bin: str,
    terraform_dir: str,
    state_file: str | None = None,
) -> dict[str, str]:
    if state_file:
        payload = json.loads(Path(state_file).read_text(encoding="utf-8")).get("outputs", {})
        return tunnel_tokens_from_output(payload)

    payload = run_json([terraform_bin, f"-chdir={terraform_dir}", "output", "-json"])
    return tunnel_tokens_from_output(payload)


def update_oci_tfvars(tfvars_path: Path, secret_ids_by_role: dict[str, str]) -> None:
    merge_runtime_secret_ocids(
        tfvars_path,
        {role: {SECRET_KEYS[role]: secret_id} for role, secret_id in secret_ids_by_role.items()},
    )


def main() -> int:
    args = parse_args()
    tfvars_path = Path(args.oci_tfvars)
    if not tfvars_path.is_file():
        raise SystemExit(
            f"Terraform variables file not found: {tfvars_path}. "
            "Create it from terraform/oci/terraform.tfvars.json.example."
        )
    tokens = terraform_outputs(
        args.terraform_bin,
        args.cloudflare_terraform_dir,
        args.cloudflare_state_file,
    )
    existing = list_existing_secrets(args.oci_bin, args.compartment_id, args.vault_id)
    secret_ids_by_role: dict[str, str] = {}

    for role, name in SECRET_NAMES.items():
        token = tokens[role]
        secret_id = existing.get(name)
        if secret_id:
            if current_secret_content(args.oci_bin, secret_id) == token:
                print(f"{name}: already current")
            else:
                update_secret_content(
                    oci_bin=args.oci_bin,
                    secret_id=secret_id,
                    content=token,
                    content_name="cloudflare-token",
                    dry_run=args.dry_run,
                )
                print(f"{name}: updated")
        else:
            secret_id = create_secret(
                oci_bin=args.oci_bin,
                compartment_id=args.compartment_id,
                vault_id=args.vault_id,
                key_id=args.key_id,
                name=name,
                content=token,
                dry_run=args.dry_run,
                description="VN News Cloudflare tunnel token sourced from Terraform output.",
                managed_by="cloudflare-secret-sync",
            )
            print(f"{name}: created")
        secret_ids_by_role[role] = secret_id

    if not args.dry_run:
        update_oci_tfvars(tfvars_path, secret_ids_by_role)
        print(f"updated {args.oci_tfvars} with Cloudflare tunnel secret OCIDs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
