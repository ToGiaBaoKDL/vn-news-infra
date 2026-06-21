from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
LOCALS_TF = REPO_ROOT / "terraform" / "oci" / "locals.tf"
BACKUPS_TF = REPO_ROOT / "terraform" / "oci" / "backups.tf"

EXPECTED_NODES = {
    "tgb-data-1": {"ocpus": 1, "memory_gb": 6, "private_ip": "10.0.10.16"},
    "tgb-control-1": {"ocpus": 1, "memory_gb": 6, "private_ip": "10.0.10.221"},
    "tgb-processing-1": {"ocpus": 2, "memory_gb": 12, "private_ip": "10.0.10.50"},
}

EXPECTED = {
    "shape": "VM.Standard.A1.Flex",
    "boot_volume_size_gb": 50,
    "data_volume_size_gb": 50,
    "instance_count": 3,
    "total_ocpus": 4,
    "total_memory_gb": 24,
    "total_live_block_storage_gb": 200,
    "recovery_bucket_budget_gib": 20,
}


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def number(text: str, name: str) -> int:
    match = re.search(rf"^\s*{re.escape(name)}\s*=\s*(\d+)\s*$", text, re.MULTILINE)
    if not match:
        raise ValueError(f"missing numeric local: {name}")
    return int(match.group(1))


def string(text: str, name: str) -> str:
    match = re.search(rf'^\s*{re.escape(name)}\s*=\s*"([^"]+)"\s*$', text, re.MULTILINE)
    if not match:
        raise ValueError(f"missing string local: {name}")
    return match.group(1)


def node_block(text: str, name: str) -> str:
    pattern = rf"^\s*{re.escape(name)}\s*=\s*\{{(?P<body>.*?)^\s*\}}"
    match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    if not match:
        raise ValueError(f"missing node block: {name}")
    return match.group("body")


def main() -> int:
    text = LOCALS_TF.read_text()

    if string(text, "shape") != EXPECTED["shape"]:
        return fail("Terraform shape must remain VM.Standard.A1.Flex.")

    boot_gb = number(text, "boot_volume_size_gb")
    data_gb = number(text, "data_volume_size_gb")
    if boot_gb != EXPECTED["boot_volume_size_gb"] or data_gb != EXPECTED["data_volume_size_gb"]:
        return fail("Terraform volume sizes must remain 3 x 50 GB boot and 1 x 50 GB data.")

    total_ocpus = 0
    total_memory_gb = 0
    for name, expected in EXPECTED_NODES.items():
        body = node_block(text, name)
        ocpus = number(body, "ocpus")
        memory_gb = number(body, "memory_gb")
        private_ip = string(body, "private_ip")
        if (
            ocpus != expected["ocpus"]
            or memory_gb != expected["memory_gb"]
            or private_ip != expected["private_ip"]
        ):
            return fail(
                f"{name} must remain {expected['ocpus']} OCPU / "
                f"{expected['memory_gb']} GB at {expected['private_ip']}."
            )
        total_ocpus += ocpus
        total_memory_gb += memory_gb

    instance_count = len(EXPECTED_NODES)
    total_storage_gb = (boot_gb * instance_count) + data_gb

    if instance_count != EXPECTED["instance_count"]:
        return fail("Terraform must declare exactly 3 nodes.")
    if total_ocpus != EXPECTED["total_ocpus"]:
        return fail("Terraform must stay at 4 total OCPUs.")
    if total_memory_gb != EXPECTED["total_memory_gb"]:
        return fail("Terraform must stay at 24 total GB memory.")
    if total_storage_gb != EXPECTED["total_live_block_storage_gb"]:
        return fail("Terraform must stay at 200 total GB live boot and block storage.")

    if number(text, "recovery_bucket_budget_gib") != EXPECTED["recovery_bucket_budget_gib"]:
        return fail("Terraform recovery bucket budget must remain 20 GiB.")

    backups = BACKUPS_TF.read_text()
    if backups.count('resource "oci_core_volume_backup_policy_assignment"') != 2:
        return fail("Terraform must keep data-volume and control-boot backup policy assignments.")

    print("Terraform Always Free guardrails match the expected matrix.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
