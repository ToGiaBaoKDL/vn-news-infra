from __future__ import annotations

import json
from pathlib import Path

from scripts.resource_manager.render_variables import render_variables
from scripts.secrets.catalog import ROLE_NAMES, ROLE_SECRET_KEYS, SECRET_ENV_VARS
from scripts.secrets.terraform_vars import (
    merge_runtime_secret_ocids,
    read_runtime_secret_ocids,
    write_runtime_secret_ocids,
)


def tfvars_payload() -> dict:
    return {
        "alarm_notification_email": "",
        "arm64_ubuntu_image_ocid": "ocid1.image.test",
        "availability_domain": "auto",
        "compartment_ocid": "ocid1.compartment.test",
        "region": "ap-singapore-1",
        "runtime_secret_ocids": {role: {} for role in ROLE_NAMES},
        "ssh_authorized_key": "ssh-ed25519 test",
        "ssh_ingress_cidrs": ["0.0.0.0/0"],
        "tenancy_ocid": "ocid1.tenancy.test",
    }


def write_tfvars(path: Path) -> None:
    path.write_text(json.dumps(tfvars_payload()), encoding="utf-8")


def secret_id(key: str) -> str:
    return f"ocid1.vaultsecret.test.{key}"


def test_named_secret_tfvars_preserve_unrelated_variables(tmp_path: Path) -> None:
    path = tmp_path / "terraform.tfvars.json"
    write_tfvars(path)

    write_runtime_secret_ocids(
        path,
        {
            "data": {"polaris_client_credentials": secret_id("polaris")},
            "control": {},
            "processing": {},
        },
    )
    merge_runtime_secret_ocids(
        path,
        {"data": {"cloudflare_data_tunnel_token": secret_id("cloudflare-data")}},
    )

    payload = json.loads(path.read_text(encoding="utf-8"))
    assert payload["region"] == "ap-singapore-1"
    assert read_runtime_secret_ocids(path)["data"] == {
        "cloudflare_data_tunnel_token": secret_id("cloudflare-data"),
        "polaris_client_credentials": secret_id("polaris"),
    }


def test_resource_manager_renderer_serializes_named_secret_map(tmp_path: Path) -> None:
    path = tmp_path / "terraform.tfvars.json"
    payload = tfvars_payload()
    payload["runtime_secret_ocids"]["data"] = {"polaris_client_credentials": secret_id("polaris")}
    path.write_text(json.dumps(payload), encoding="utf-8")

    variables = render_variables(path)

    runtime_secrets = json.loads(variables["runtime_secret_ocids"])
    assert runtime_secrets["data"]["polaris_client_credentials"] == secret_id("polaris")
    assert variables["compartment_ocid"] == "ocid1.compartment.test"


def test_every_role_secret_has_an_env_variable() -> None:
    assigned = {key for keys in ROLE_SECRET_KEYS.values() for key in keys}
    assert assigned <= set(SECRET_ENV_VARS)
