from __future__ import annotations

import argparse
import base64
import json
import os
import secrets
import string
import subprocess
import tempfile
from pathlib import Path

from runtime_secret_tfvars import merge_runtime_secret_ocids


SECRET_NAMES = {
    "seaweedfs_s3_config": "tgb-vn-news-seaweedfs-s3-config",
    "storage_admin_s3_credentials": "tgb-vn-news-storage-admin-s3-credentials",
    "ingestion_s3_credentials": "tgb-vn-news-ingestion-s3-credentials",
    "curated_writer_s3_credentials": "tgb-vn-news-curated-writer-s3-credentials",
    "airflow_db_password": "tgb-vn-news-airflow-db-password",
    "airflow_api_jwt_secret": "tgb-vn-news-airflow-api-jwt-secret",
    "airflow_fernet_key": "tgb-vn-news-airflow-fernet-key",
    "airflow_admin_password": "tgb-vn-news-airflow-admin-password",
}

ROLE_SECRET_KEYS = {
    "data": ("seaweedfs_s3_config", "storage_admin_s3_credentials"),
    "control": (
        "ingestion_s3_credentials",
        "airflow_db_password",
        "airflow_api_jwt_secret",
        "airflow_fernet_key",
        "airflow_admin_password",
    ),
    "processing": ("ingestion_s3_credentials", "curated_writer_s3_credentials"),
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


def seaweedfs_identity(name: str, access_key: str, secret_key: str) -> dict:
    return {
        "name": name,
        "credentials": [
            {
                "accessKey": access_key,
                "secretKey": secret_key,
            }
        ],
        "actions": ["Read", "Write", "List", "Tagging"],
    }


def s3_credentials(access_key: str, secret_key: str) -> str:
    return (
        "[default]\n"
        f"aws_access_key_id={access_key}\n"
        f"aws_secret_access_key={secret_key}\n"
    )


def curated_writer_payload() -> tuple[dict, str]:
    access_key = f"vnnewscurated{random_alnum(20)}"
    secret_key = random_alnum(56)
    return (
        seaweedfs_identity("vn-news-curated-writer", access_key, secret_key),
        s3_credentials(access_key, secret_key),
    )


def secret_payloads() -> dict[str, str]:
    storage_admin_access_key = f"vnnewsadmin{random_alnum(20)}"
    storage_admin_secret_key = random_alnum(56)
    ingestion_access_key = f"vnnewsingest{random_alnum(20)}"
    ingestion_secret_key = random_alnum(56)
    curated_writer_identity, curated_writer_credentials = curated_writer_payload()

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
            curated_writer_identity,
        ]
    }
    return {
        "seaweedfs_s3_config": json.dumps(seaweedfs_config, separators=(",", ":")),
        "storage_admin_s3_credentials": s3_credentials(
            storage_admin_access_key, storage_admin_secret_key
        ),
        "ingestion_s3_credentials": s3_credentials(
            ingestion_access_key, ingestion_secret_key
        ),
        "curated_writer_s3_credentials": curated_writer_credentials,
        "airflow_db_password": random_alnum(40),
        "airflow_api_jwt_secret": random_alnum(64),
        "airflow_fernet_key": fernet_key(),
        "airflow_admin_password": random_alnum(40),
    }


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


def update_secret_content(
    *,
    oci_bin: str,
    secret_id: str,
    content: str,
    content_name: str,
    dry_run: bool,
) -> None:
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
            content_name,
            "--force",
            "--wait-for-state",
            "ACTIVE",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


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
        "secretContentContent": base64.b64encode(content.encode("utf-8")).decode(
            "ascii"
        ),
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
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    return payload["data"]["id"]


def runtime_secret_ocids_by_role(
    secret_ids_by_key: dict[str, str],
) -> dict[str, list[str]]:
    secret_ids_by_role = {}
    for role, secret_keys in ROLE_SECRET_KEYS.items():
        secret_ids_by_role[role] = [secret_ids_by_key[key] for key in secret_keys]
    return secret_ids_by_role


def credentials_from_seaweedfs_identity(identity: dict) -> str:
    try:
        credential = identity["credentials"][0]
        return s3_credentials(credential["accessKey"], credential["secretKey"])
    except (KeyError, IndexError, TypeError) as exc:
        raise SystemExit(
            "SeaweedFS curated-writer identity is missing credentials."
        ) from exc


def add_curated_writer_to_existing_secrets(
    *,
    args: argparse.Namespace,
    existing_by_name: dict[str, str],
) -> dict[str, str]:
    config_secret_id = existing_by_name[SECRET_NAMES["seaweedfs_s3_config"]]
    config = json.loads(current_secret_content(args.oci_bin, config_secret_id))
    identities = config.setdefault("identities", [])
    curated_identity = next(
        (
            identity
            for identity in identities
            if identity.get("name") == "vn-news-curated-writer"
        ),
        None,
    )

    if curated_identity is None:
        curated_identity, curated_credentials = curated_writer_payload()
        identities.append(curated_identity)
        update_secret_content(
            oci_bin=args.oci_bin,
            secret_id=config_secret_id,
            content=json.dumps(config, separators=(",", ":")),
            content_name="curated-writer-added",
            dry_run=args.dry_run,
        )
        print("updated SeaweedFS S3 config with vn-news-curated-writer")
    else:
        curated_credentials = credentials_from_seaweedfs_identity(curated_identity)
        print("SeaweedFS S3 config already contains vn-news-curated-writer")

    curated_secret_id = create_secret(
        oci_bin=args.oci_bin,
        compartment_id=args.compartment_id,
        vault_id=args.vault_id,
        key_id=args.key_id,
        name=SECRET_NAMES["curated_writer_s3_credentials"],
        content=curated_credentials,
        dry_run=args.dry_run,
    )
    print(
        f"created {SECRET_NAMES['curated_writer_s3_credentials']}: {curated_secret_id}"
    )

    secret_ids_by_key = {
        key: existing_by_name[name]
        for key, name in SECRET_NAMES.items()
        if key != "curated_writer_s3_credentials"
    }
    secret_ids_by_key["curated_writer_s3_credentials"] = curated_secret_id
    return secret_ids_by_key


def main() -> int:
    args = parse_args()
    tfvars_path = Path(args.tfvars)
    required_names = set(SECRET_NAMES.values())

    existing_by_name = list_existing_secrets(
        args.oci_bin, args.compartment_id, args.vault_id
    )
    existing_required = required_names & set(existing_by_name)
    missing_names = required_names - existing_required
    if existing_required == required_names:
        secret_ids_by_key = {
            key: existing_by_name[name] for key, name in SECRET_NAMES.items()
        }
        print(
            "All required runtime secrets already exist; updating tfvars with existing OCIDs."
        )
    elif existing_required and missing_names == {
        SECRET_NAMES["curated_writer_s3_credentials"]
    }:
        secret_ids_by_key = add_curated_writer_to_existing_secrets(
            args=args,
            existing_by_name=existing_by_name,
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
        merge_runtime_secret_ocids(
            tfvars_path, runtime_secret_ocids_by_role(secret_ids_by_key)
        )
        print(f"updated {tfvars_path} with runtime_secret_ocids")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
