from __future__ import annotations

import re
from pathlib import Path


ROLE_NAMES = ("data", "control", "processing")


def read_runtime_secret_ocids(tfvars_path: Path) -> dict[str, list[str]]:
    roles = {role: [] for role in ROLE_NAMES}
    if not tfvars_path.exists():
        return roles

    text = tfvars_path.read_text(encoding="utf-8")
    match = re.search(r"(?ms)^runtime_secret_ocids\s*=\s*\{(.*?)^\}", text)
    if not match:
        return roles

    block = match.group(1)
    for role in ROLE_NAMES:
        role_match = re.search(rf"(?ms)^\s*{role}\s*=\s*\[(.*?)\]", block)
        if role_match:
            roles[role] = re.findall(
                r'"(ocid1\.vaultsecret\.[^"]+)"', role_match.group(1)
            )
    return roles


def render_runtime_secret_ocids(roles: dict[str, list[str]]) -> str:
    lines = ["runtime_secret_ocids = {"]
    for role in ROLE_NAMES:
        lines.append(f"  {role} = [")
        for secret_id in roles.get(role, []):
            lines.append(f'    "{secret_id}",')
        lines.append("  ]")
    lines.append("}")
    return "\n".join(lines)


def write_runtime_secret_ocids(tfvars_path: Path, roles: dict[str, list[str]]) -> None:
    replacement = render_runtime_secret_ocids(roles)
    text = tfvars_path.read_text(encoding="utf-8") if tfvars_path.exists() else ""
    pattern = r"(?ms)^runtime_secret_ocids\s*=\s*\{.*?^\}"
    if re.search(pattern, text):
        updated = re.sub(pattern, replacement, text)
    else:
        updated = text.rstrip() + "\n\n" + replacement + "\n"
    tfvars_path.write_text(updated, encoding="utf-8")


def merge_runtime_secret_ocids(
    tfvars_path: Path,
    secret_ids_by_role: dict[str, list[str]],
) -> None:
    roles = read_runtime_secret_ocids(tfvars_path)
    unknown_roles = sorted(set(secret_ids_by_role) - set(ROLE_NAMES))
    if unknown_roles:
        raise ValueError(f"Unknown runtime secret roles: {unknown_roles}")

    for role, secret_ids in secret_ids_by_role.items():
        for secret_id in secret_ids:
            if secret_id not in roles[role]:
                roles[role].append(secret_id)
    write_runtime_secret_ocids(tfvars_path, roles)
