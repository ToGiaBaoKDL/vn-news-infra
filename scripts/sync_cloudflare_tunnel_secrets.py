from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import tempfile
from pathlib import Path


SECRET_NAMES = {
    "control": "tgb-vn-news-cloudflare-control-tunnel-token",
    "data": "tgb-vn-news-cloudflare-data-tunnel-token",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync Cloudflare tunnel tokens from Terraform output into OCI Vault."
    )
    parser.add_argument("--compartment-id", required=True)
    parser.add_argument("--vault-id", required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--cloudflare-terraform-dir", default="terraform/cloudflare")
    parser.add_argument("--oci-tfvars", default="terraform/oci/terraform.tfvars")
    parser.add_argument("--oci-bin", default="oci")
    parser.add_argument("--terraform-bin", default="terraform")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def run_json(command: list[str]) -> dict:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    if not result.stdout.strip():
        return {}
    return json.loads(result.stdout)


def terraform_outputs(terraform_bin: str, terraform_dir: str) -> dict[str, str]:
    payload = run_json([terraform_bin, f"-chdir={terraform_dir}", "output", "-json"])
    try:
        tokens = payload["cloudflare_tunnel_tokens"]["value"]
    except KeyError as exc:
        raise SystemExit("Missing cloudflare_tunnel_tokens Terraform output.") from exc
    missing = sorted(set(SECRET_NAMES) - set(tokens))
    if missing:
        raise SystemExit(f"Missing tunnel tokens for roles: {missing}")
    return {role: str(tokens[role]) for role in SECRET_NAMES}


def list_existing_secrets(
    oci_bin: str, compartment_id: str, vault_id: str
) -> dict[str, str]:
    payload = run_json(
        [
            oci_bin,
            "vault",
            "secret",
            "list",
            "--compartment-id",
            compartment_id,
            "--vault-id",
            vault_id,
            "--all",
        ]
    )
    secrets: dict[str, str] = {}
    for item in payload.get("data", []):
        if item.get("lifecycle-state") == "ACTIVE":
            secrets[item["secret-name"]] = item["id"]
    return secrets


def current_secret_content(oci_bin: str, secret_id: str) -> str:
    payload = run_json(
        [
            oci_bin,
            "secrets",
            "secret-bundle",
            "get",
            "--secret-id",
            secret_id,
        ]
    )
    encoded = payload["data"]["secret-bundle-content"]["content"]
    return base64.b64decode(encoded).decode("utf-8")


def write_json_temp(payload: dict) -> str:
    fd, path = tempfile.mkstemp(prefix="vn-news-cloudflare-secret-", suffix=".json")
    with open(fd, "w", encoding="utf-8") as file:
        json.dump(payload, file, separators=(",", ":"))
        file.write("\n")
    return path


def create_secret(
    *,
    oci_bin: str,
    compartment_id: str,
    vault_id: str,
    key_id: str,
    name: str,
    content: str,
    dry_run: bool,
) -> str:
    if dry_run:
        return f"dry-run:{name}"
    request = {
        "compartmentId": compartment_id,
        "vaultId": vault_id,
        "keyId": key_id,
        "secretName": name,
        "description": "VN News Cloudflare tunnel token. Value is sourced from Cloudflare Terraform output.",
        "secretContentContent": base64.b64encode(content.encode("utf-8")).decode(
            "ascii"
        ),
        "secretContentName": "v1",
        "secretContentStage": "CURRENT",
        "freeformTags": {
            "project": "vn-news",
            "environment": "prod",
            "managed-by": "cloudflare-secret-sync",
        },
        "waitForState": ["ACTIVE"],
        "maxWaitSeconds": 1200,
        "waitIntervalSeconds": 10,
    }
    path = write_json_temp(request)
    try:
        payload = run_json(
            [
                oci_bin,
                "vault",
                "secret",
                "create-base64",
                "--from-json",
                f"file://{path}",
            ]
        )
    finally:
        Path(path).unlink(missing_ok=True)
    return payload["data"]["id"]


def update_secret(oci_bin: str, secret_id: str, content: str, dry_run: bool) -> None:
    if dry_run:
        return
    encoded = base64.b64encode(content.encode("utf-8")).decode("ascii")
    subprocess.run(
        [
            oci_bin,
            "vault",
            "secret",
            "update-base64",
            "--secret-id",
            secret_id,
            "--secret-content-content",
            encoded,
            "--secret-content-stage",
            "CURRENT",
            "--secret-content-name",
            "cloudflare-token",
            "--force",
            "--wait-for-state",
            "ACTIVE",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def existing_runtime_secret_ocids(tfvars_path: Path) -> dict[str, list[str]]:
    if not tfvars_path.exists():
        return {"data": [], "control": [], "processing": []}
    text = tfvars_path.read_text(encoding="utf-8")
    match = re.search(r"(?ms)^runtime_secret_ocids\s*=\s*\{(.*?)^\}", text)
    roles = {"data": [], "control": [], "processing": []}
    if not match:
        return roles
    block = match.group(1)
    for role in roles:
        role_match = re.search(rf"(?ms)^\s*{role}\s*=\s*\[(.*?)\]", block)
        if role_match:
            roles[role] = re.findall(
                r'"(ocid1\.vaultsecret\.[^"]+)"', role_match.group(1)
            )
    return roles


def render_runtime_secret_ocids(roles: dict[str, list[str]]) -> str:
    lines = ["runtime_secret_ocids = {"]
    for role in ("data", "control", "processing"):
        lines.append(f"  {role} = [")
        for secret_id in roles.get(role, []):
            lines.append(f'    "{secret_id}",')
        lines.append("  ]")
    lines.append("}")
    return "\n".join(lines)


def update_oci_tfvars(tfvars_path: Path, secret_ids_by_role: dict[str, str]) -> None:
    roles = existing_runtime_secret_ocids(tfvars_path)
    for role, secret_id in secret_ids_by_role.items():
        if secret_id not in roles[role]:
            roles[role].append(secret_id)
    replacement = render_runtime_secret_ocids(roles)

    text = tfvars_path.read_text(encoding="utf-8") if tfvars_path.exists() else ""
    pattern = r"(?ms)^runtime_secret_ocids\s*=\s*\{.*?^\}"
    if re.search(pattern, text):
        updated = re.sub(pattern, replacement, text)
    else:
        updated = text.rstrip() + "\n\n" + replacement + "\n"
    tfvars_path.write_text(updated, encoding="utf-8")


def main() -> int:
    args = parse_args()
    tokens = terraform_outputs(args.terraform_bin, args.cloudflare_terraform_dir)
    existing = list_existing_secrets(args.oci_bin, args.compartment_id, args.vault_id)
    secret_ids_by_role: dict[str, str] = {}

    for role, name in SECRET_NAMES.items():
        token = tokens[role]
        secret_id = existing.get(name)
        if secret_id:
            if current_secret_content(args.oci_bin, secret_id) == token:
                print(f"{name}: already current")
            else:
                update_secret(args.oci_bin, secret_id, token, args.dry_run)
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
            )
            print(f"{name}: created")
        secret_ids_by_role[role] = secret_id

    if not args.dry_run:
        update_oci_tfvars(Path(args.oci_tfvars), secret_ids_by_role)
        print(f"updated {args.oci_tfvars} with Cloudflare tunnel secret OCIDs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
