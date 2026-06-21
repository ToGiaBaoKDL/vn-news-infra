from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from scripts.secrets.catalog import ROLE_NAMES


def load_tfvars(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"Terraform variables must be a JSON object: {path}")
    return payload


def write_tfvars(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    path.chmod(0o600)


def read_runtime_secret_ocids(path: Path) -> dict[str, dict[str, str]]:
    payload = load_tfvars(path)
    configured = payload.get("runtime_secret_ocids", {})
    if not isinstance(configured, dict):
        raise ValueError("runtime_secret_ocids must be an object")

    roles: dict[str, dict[str, str]] = {role: {} for role in ROLE_NAMES}
    unknown_roles = sorted(set(configured) - set(ROLE_NAMES))
    if unknown_roles:
        raise ValueError(f"Unknown runtime secret roles: {unknown_roles}")
    for role, secrets in configured.items():
        if not isinstance(secrets, dict):
            raise ValueError(f"runtime_secret_ocids.{role} must be an object")
        roles[role] = {str(key): str(value) for key, value in secrets.items()}
    return roles


def write_runtime_secret_ocids(
    path: Path,
    secret_ids_by_role: dict[str, dict[str, str]],
) -> None:
    unknown_roles = sorted(set(secret_ids_by_role) - set(ROLE_NAMES))
    if unknown_roles:
        raise ValueError(f"Unknown runtime secret roles: {unknown_roles}")
    payload = load_tfvars(path)
    payload["runtime_secret_ocids"] = {
        role: dict(sorted(secret_ids_by_role.get(role, {}).items())) for role in ROLE_NAMES
    }
    write_tfvars(path, payload)


def merge_runtime_secret_ocids(
    path: Path,
    secret_ids_by_role: dict[str, dict[str, str]],
) -> None:
    roles = read_runtime_secret_ocids(path)
    unknown_roles = sorted(set(secret_ids_by_role) - set(ROLE_NAMES))
    if unknown_roles:
        raise ValueError(f"Unknown runtime secret roles: {unknown_roles}")
    for role, secrets in secret_ids_by_role.items():
        roles[role].update(secrets)
    write_runtime_secret_ocids(path, roles)
