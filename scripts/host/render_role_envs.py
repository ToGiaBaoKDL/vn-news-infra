from __future__ import annotations

import argparse
import shlex
from pathlib import Path

from scripts.secrets.catalog import ROLE_NAMES, ROLE_SECRET_KEYS, SECRET_ENV_VARS
from scripts.secrets.terraform_vars import load_tfvars, read_runtime_secret_ocids


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render deployable role env files from templates and named secret OCIDs."
    )
    parser.add_argument("--tfvars", default="terraform/oci/terraform.tfvars.json")
    parser.add_argument("--templates-dir", default="env")
    parser.add_argument("--output-dir", required=True)
    return parser.parse_args()


def replace_env_values(template: str, replacements: dict[str, str]) -> str:
    rendered = []
    replaced: set[str] = set()
    for line in template.splitlines():
        key, separator, _ = line.partition("=")
        if separator and key in replacements:
            rendered.append(f"{key}={replacements[key]}")
            replaced.add(key)
        else:
            rendered.append(line)
    missing = sorted(set(replacements) - replaced)
    if missing:
        raise ValueError(f"Role env template is missing secret variables: {missing}")
    return "\n".join(rendered) + "\n"


def render_role_envs(tfvars_path: Path, templates_dir: Path, output_dir: Path) -> None:
    tfvars = load_tfvars(tfvars_path)
    secret_ids_by_role = read_runtime_secret_ocids(tfvars_path)
    ssh_ingress_cidrs = tfvars.get("ssh_ingress_cidrs", [])
    if not isinstance(ssh_ingress_cidrs, list) or not ssh_ingress_cidrs:
        raise ValueError("ssh_ingress_cidrs must be a non-empty list")
    if not all(isinstance(cidr, str) and cidr.strip() for cidr in ssh_ingress_cidrs):
        raise ValueError("ssh_ingress_cidrs must contain non-empty strings")
    ssh_entries = " ".join(sorted(ssh_ingress_cidrs))
    output_dir.mkdir(parents=True, exist_ok=True)
    for role in ROLE_NAMES:
        missing = [key for key in ROLE_SECRET_KEYS[role] if key not in secret_ids_by_role[role]]
        if missing:
            raise ValueError(f"Missing {role} runtime secret OCIDs: {missing}")
        replacements = {
            SECRET_ENV_VARS[key]: secret_ids_by_role[role][key] for key in ROLE_SECRET_KEYS[role]
        }
        replacements["VN_NEWS_SSH_INGRESS_CIDRS"] = shlex.quote(ssh_entries)
        template_path = templates_dir / f"{role}.env.example"
        output_path = output_dir / f"{role}.env"
        output_path.write_text(
            replace_env_values(template_path.read_text(encoding="utf-8"), replacements),
            encoding="utf-8",
        )
        output_path.chmod(0o600)


def main() -> None:
    args = parse_args()
    render_role_envs(Path(args.tfvars), Path(args.templates_dir), Path(args.output_dir))


if __name__ == "__main__":
    main()
