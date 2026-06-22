#!/usr/bin/env bash
set -euo pipefail

role="${1:?usage: scripts/host/install_role_env.sh <data|control|processing> <env-file>}"
source_file="${2:?rendered env file is required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$script_dir/../lib/common.sh"

require_role "$role" data control processing
require_root
if [[ ! -f "$source_file" ]]; then
  echo "Rendered role env file not found: $source_file" >&2
  exit 1
fi
if grep -Eq '_SECRET_OCID=.*replace-with-' "$source_file"; then
  echo "Rendered role env still contains secret OCID placeholders: $source_file" >&2
  exit 1
fi

install -d -m 0750 -o root -g vn-news /etc/vn-news/env
install -m 0640 -o root -g vn-news "$source_file" "/etc/vn-news/env/${role}.env"
echo "installed role environment: $role"
