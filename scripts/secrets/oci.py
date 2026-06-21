from __future__ import annotations

import base64
import json
import os
import subprocess
import tempfile
from pathlib import Path


def run_json(command: list[str]) -> dict:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return json.loads(result.stdout) if result.stdout.strip() else {}


def list_existing_secrets(
    oci_bin: str,
    compartment_id: str,
    vault_id: str,
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
    return {
        item["secret-name"]: item["id"]
        for item in payload.get("data", [])
        if item.get("lifecycle-state") == "ACTIVE"
    }


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


def create_secret(
    *,
    oci_bin: str,
    compartment_id: str,
    vault_id: str,
    key_id: str,
    name: str,
    content: str,
    dry_run: bool,
    description: str = "VN News runtime secret. Value is generated outside Terraform.",
    managed_by: str = "runtime-secret-script",
) -> str:
    if dry_run:
        return f"dry-run:{name}"

    request = {
        "compartmentId": compartment_id,
        "vaultId": vault_id,
        "keyId": key_id,
        "secretName": name,
        "description": description,
        "secretContentContent": base64.b64encode(content.encode("utf-8")).decode("ascii"),
        "secretContentName": "v1",
        "secretContentStage": "CURRENT",
        "freeformTags": {
            "project": "vn-news",
            "environment": "prod",
            "managed-by": managed_by,
        },
        "waitForState": ["ACTIVE"],
        "maxWaitSeconds": 1200,
        "waitIntervalSeconds": 10,
    }
    fd, temporary_path = tempfile.mkstemp(prefix="vn-news-secret-", suffix=".json")
    path = Path(temporary_path)
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
        path.unlink(missing_ok=True)
    return payload["data"]["id"]


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
    )
