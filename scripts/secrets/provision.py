from __future__ import annotations

import argparse
import base64
import json
import os
import secrets
import string
from pathlib import Path

from scripts.secrets.catalog import (
    GENERATED_SECRET_KEYS,
    LEGACY_STORAGE_ADMIN_IDENTITY_NAME,
    ROLE_SECRET_KEYS,
    SECRET_NAMES,
    STORAGE_ADMIN_IDENTITY_NAME,
)
from scripts.secrets.oci import (
    create_secret,
    current_secret_content,
    list_existing_secrets,
    update_secret_content,
)
from scripts.secrets.terraform_vars import write_runtime_secret_ocids


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Provision runtime secrets in OCI Vault and update local Terraform variables."
    )
    parser.add_argument("--compartment-id", required=True)
    parser.add_argument("--vault-id", required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--tfvars", default="terraform/oci/terraform.tfvars.json")
    parser.add_argument("--oci-bin", default=os.environ.get("OCI_BIN", "oci"))
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def random_alnum(length: int) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def fernet_key() -> str:
    return base64.urlsafe_b64encode(os.urandom(32)).decode("ascii")


def s3_credentials(access_key: str, secret_key: str) -> str:
    return f"[default]\naws_access_key_id={access_key}\naws_secret_access_key={secret_key}\n"


def pending_polaris_client_credentials() -> str:
    return json.dumps(
        {"status": "pending-polaris-runtime-principal"},
        separators=(",", ":"),
    )


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
    return {
        "seaweedfs_s3_config": json.dumps(seaweedfs_config, separators=(",", ":")),
        "storage_admin_s3_credentials": s3_credentials(
            storage_admin_access_key, storage_admin_secret_key
        ),
        "ingestion_s3_credentials": s3_credentials(ingestion_access_key, ingestion_secret_key),
        "polaris_client_credentials": pending_polaris_client_credentials(),
        "polaris_db_password": random_alnum(40),
        "polaris_bootstrap_admin": random_alnum(56),
        "spark_rpc_auth_secret": random_alnum(64),
        "airflow_db_password": random_alnum(40),
        "airflow_api_jwt_secret": random_alnum(64),
        "airflow_fernet_key": fernet_key(),
        "airflow_admin_password": random_alnum(40),
    }


def runtime_secret_ocids_by_role(
    secret_ids_by_key: dict[str, str],
) -> dict[str, dict[str, str]]:
    secret_ids_by_role = {}
    for role, secret_keys in ROLE_SECRET_KEYS.items():
        secret_ids_by_role[role] = {
            key: secret_ids_by_key[key] for key in secret_keys if key in secret_ids_by_key
        }
    return secret_ids_by_role


def credentials_from_seaweedfs_identity(identity: dict) -> str:
    try:
        credential = identity["credentials"][0]
        return s3_credentials(credential["accessKey"], credential["secretKey"])
    except (KeyError, IndexError, TypeError) as exc:
        name = identity.get("name", "unknown") if isinstance(identity, dict) else "unknown"
        raise SystemExit(f"SeaweedFS identity is missing credentials: {name}") from exc


def migrate_existing_runtime_secrets(
    *,
    args: argparse.Namespace,
    existing_by_name: dict[str, str],
    missing_names: set[str],
) -> dict[str, str]:
    config_secret_id = existing_by_name[SECRET_NAMES["seaweedfs_s3_config"]]
    config = json.loads(current_secret_content(args.oci_bin, config_secret_id))
    identities = config.setdefault("identities", [])
    config_changed = False
    payloads = secret_payloads()
    credentials_to_create: dict[str, str] = {}

    storage_admin_name = SECRET_NAMES["storage_admin_s3_credentials"]
    storage_admin_identity = next(
        (
            identity
            for identity in identities
            if identity.get("name")
            in {STORAGE_ADMIN_IDENTITY_NAME, LEGACY_STORAGE_ADMIN_IDENTITY_NAME}
        ),
        None,
    )
    if storage_admin_identity is None:
        raise SystemExit("SeaweedFS storage-admin identity is missing.")
    if storage_admin_identity.get("name") == LEGACY_STORAGE_ADMIN_IDENTITY_NAME:
        storage_admin_identity["name"] = STORAGE_ADMIN_IDENTITY_NAME
        config_changed = True
    if storage_admin_name in missing_names:
        credentials_to_create["storage_admin_s3_credentials"] = credentials_from_seaweedfs_identity(
            storage_admin_identity
        )

    for key in (
        "polaris_client_credentials",
        "polaris_db_password",
        "polaris_bootstrap_admin",
        "spark_rpc_auth_secret",
    ):
        if SECRET_NAMES[key] in missing_names:
            credentials_to_create[key] = payloads[key]

    if config_changed:
        update_secret_content(
            oci_bin=args.oci_bin,
            secret_id=config_secret_id,
            content=json.dumps(config, separators=(",", ":")),
            content_name="storage-role-migration",
            dry_run=args.dry_run,
        )
        print("updated SeaweedFS S3 config identities")

    created_secret_ids: dict[str, str] = {}
    for key, content in credentials_to_create.items():
        name = SECRET_NAMES[key]
        created_secret_ids[key] = create_secret(
            oci_bin=args.oci_bin,
            compartment_id=args.compartment_id,
            vault_id=args.vault_id,
            key_id=args.key_id,
            name=name,
            content=content,
            dry_run=args.dry_run,
        )
        print(f"created {name}")

    secret_ids_by_key = {
        key: existing_by_name[name]
        for key, name in SECRET_NAMES.items()
        if name in existing_by_name and key not in created_secret_ids
    }
    secret_ids_by_key.update(created_secret_ids)
    return secret_ids_by_key


def main() -> int:
    args = parse_args()
    tfvars_path = Path(args.tfvars)
    if not tfvars_path.is_file():
        raise SystemExit(
            f"Terraform variables file not found: {tfvars_path}. "
            "Create it from terraform/oci/terraform.tfvars.json.example."
        )
    required_names = {SECRET_NAMES[key] for key in GENERATED_SECRET_KEYS}

    existing_by_name = list_existing_secrets(args.oci_bin, args.compartment_id, args.vault_id)
    existing_required = required_names & set(existing_by_name)
    missing_names = required_names - existing_required
    incremental_names = {
        SECRET_NAMES["storage_admin_s3_credentials"],
        SECRET_NAMES["polaris_client_credentials"],
        SECRET_NAMES["polaris_db_password"],
        SECRET_NAMES["polaris_bootstrap_admin"],
        SECRET_NAMES["spark_rpc_auth_secret"],
    }
    if existing_required and missing_names <= incremental_names:
        secret_ids_by_key = migrate_existing_runtime_secrets(
            args=args,
            existing_by_name=existing_by_name,
            missing_names=missing_names,
        )
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
        for key in GENERATED_SECRET_KEYS:
            name = SECRET_NAMES[key]
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
        for key, name in SECRET_NAMES.items():
            if key not in secret_ids_by_key and name in existing_by_name:
                secret_ids_by_key[key] = existing_by_name[name]

    if not args.dry_run:
        write_runtime_secret_ocids(
            tfvars_path,
            runtime_secret_ocids_by_role(secret_ids_by_key),
        )
        print(f"updated {tfvars_path} with runtime_secret_ocids")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
