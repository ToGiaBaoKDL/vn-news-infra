from __future__ import annotations

import argparse
import base64
import json
import os
import re
import secrets
import string
import subprocess
import tempfile
from pathlib import Path


SECRET_NAMES = {
    "seaweedfs_s3_config": "tgb-vn-news-seaweedfs-s3-config",
    "storage_admin_s3_credentials": "tgb-vn-news-storage-admin-s3-credentials",
    "ingestion_s3_credentials": "tgb-vn-news-ingestion-s3-credentials",
    "airflow_db_password": "tgb-vn-news-airflow-db-password",
    "airflow_api_jwt_secret": "tgb-vn-news-airflow-api-jwt-secret",
    "airflow_fernet_key": "tgb-vn-news-airflow-fernet-key",
    "airflow_admin_password": "tgb-vn-news-airflow-admin-password",
}

ROLE_SECRET_KEYS = {
    "data": ("seaweedfs_s3_config",),
    "control": (
        "storage_admin_s3_credentials",
        "ingestion_s3_credentials",
        "airflow_db_password",
        "airflow_api_jwt_secret",
        "airflow_fernet_key",
        "airflow_admin_password",
    ),
    "processing": ("ingestion_s3_credentials",),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create Phase 1 runtime secrets in OCI Vault and update local tfvars."
    )
    parser.add_argument("--compartment-id", required=True)
    parser.add_argument("--vault-id", required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--tfvars", default="terraform/oci/terraform.tfvars")
    parser.add_argument("--oci-bin", default=os.environ.get("OCI_BIN", "oci"))
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def run_json(command: list[str]) -> dict:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    if not result.stdout.strip():
        return {}
    return json.loads(result.stdout)


def random_alnum(length: int) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def fernet_key() -> str:
    return base64.urlsafe_b64encode(os.urandom(32)).decode("ascii")


def secret_payloads() -> dict[str, str]:
    storage_admin_access_key = f"vnnewsadmin{random_alnum(20)}"
    storage_admin_secret_key = random_alnum(56)
    ingestion_access_key = f"vnnewsingest{random_alnum(20)}"
    ingestion_secret_key = random_alnum(56)

    seaweedfs_config = {
        "identities": [
            {
                "name": "vn-news-storage-admin",
                "credentials": [
                    {
                        "accessKey": storage_admin_access_key,
                        "secretKey": storage_admin_secret_key,
                    }
                ],
                "actions": ["Admin", "Read", "Write", "List", "Tagging"],
            },
            {
                "name": "vn-news-ingestion-rw",
                "credentials": [
                    {
                        "accessKey": ingestion_access_key,
                        "secretKey": ingestion_secret_key,
                    }
                ],
                "actions": ["Read", "Write", "List", "Tagging"],
            },
        ]
    }
    ingestion_credentials = (
        "[default]\n"
        f"aws_access_key_id={ingestion_access_key}\n"
        f"aws_secret_access_key={ingestion_secret_key}\n"
    )
    storage_admin_credentials = (
        "[default]\n"
        f"aws_access_key_id={storage_admin_access_key}\n"
        f"aws_secret_access_key={storage_admin_secret_key}\n"
    )
    return {
        "seaweedfs_s3_config": json.dumps(seaweedfs_config, separators=(",", ":")),
        "storage_admin_s3_credentials": storage_admin_credentials,
        "ingestion_s3_credentials": ingestion_credentials,
        "airflow_db_password": random_alnum(40),
        "airflow_api_jwt_secret": random_alnum(64),
        "airflow_fernet_key": fernet_key(),
        "airflow_admin_password": random_alnum(40),
    }


def list_existing_secrets(oci_bin: str, compartment_id: str, vault_id: str) -> dict[str, str]:
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
        "description": "VN News runtime secret. Value is generated outside Terraform.",
        "secretContentContent": base64.b64encode(content.encode("utf-8")).decode("ascii"),
        "secretContentName": "v1",
        "secretContentStage": "CURRENT",
        "freeformTags": {
            "project": "vn-news",
            "environment": "prod",
            "managed-by": "runtime-secret-script",
        },
        "waitForState": ["ACTIVE"],
        "maxWaitSeconds": 1200,
        "waitIntervalSeconds": 10,
    }
    fd, path = tempfile.mkstemp(prefix="vn-news-secret-", suffix=".json")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            json.dump(request, file, separators=(",", ":"))
            file.write("\n")
        payload = run_json([oci_bin, "vault", "secret", "create-base64", "--from-json", f"file://{path}"])
    finally:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    return payload["data"]["id"]


def hcl_list(values: tuple[str, ...]) -> str:
    rendered = ",\n".join(f'    "{value}"' for value in values)
    return f"[\n{rendered}\n  ]"


def render_runtime_secret_ocids(secret_ids_by_key: dict[str, str]) -> str:
    role_lines = []
    for role, secret_keys in ROLE_SECRET_KEYS.items():
        values = tuple(secret_ids_by_key[key] for key in secret_keys)
        role_lines.append(f"  {role} = {hcl_list(values)}")
    return "runtime_secret_ocids = {\n" + "\n".join(role_lines) + "\n}"


def update_tfvars(tfvars_path: Path, secret_ids_by_key: dict[str, str]) -> None:
    text = tfvars_path.read_text(encoding="utf-8")
    replacement = render_runtime_secret_ocids(secret_ids_by_key)
    pattern = r"(?ms)^runtime_secret_ocids\s*=\s*\{.*?^\}"
    if re.search(pattern, text):
        updated = re.sub(pattern, replacement, text)
    else:
        updated = text.rstrip() + "\n\n" + replacement + "\n"
    tfvars_path.write_text(updated, encoding="utf-8")


def main() -> int:
    args = parse_args()
    tfvars_path = Path(args.tfvars)
    required_names = set(SECRET_NAMES.values())

    existing_by_name = list_existing_secrets(args.oci_bin, args.compartment_id, args.vault_id)
    existing_required = required_names & set(existing_by_name)
    missing_names = required_names - existing_required
    if existing_required == required_names:
        secret_ids_by_key = {key: existing_by_name[name] for key, name in SECRET_NAMES.items()}
        print("All required runtime secrets already exist; updating tfvars with existing OCIDs.")
    elif existing_required:
        missing = sorted(missing_names)
        raise SystemExit(
            "Partial runtime secret set already exists. Missing: "
            + ", ".join(missing)
            + ". Create or rotate manually before rerunning."
        )
    else:
        payloads = secret_payloads()
        secret_ids_by_key = {}
        for key, name in SECRET_NAMES.items():
            secret_id = create_secret(
                oci_bin=args.oci_bin,
                compartment_id=args.compartment_id,
                vault_id=args.vault_id,
                key_id=args.key_id,
                name=name,
                content=payloads[key],
                dry_run=args.dry_run,
            )
            secret_ids_by_key[key] = secret_id
            print(f"created {name}: {secret_id}")

    if not args.dry_run:
        update_tfvars(tfvars_path, secret_ids_by_key)
        print(f"updated {tfvars_path} with runtime_secret_ocids")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
