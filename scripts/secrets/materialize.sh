#!/usr/bin/env bash
set -euo pipefail

role="${1:?role is required: data, control, or processing}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::FutureWarning}"

# shellcheck source=scripts/lib/common.sh
source "$script_dir/../lib/common.sh"
# shellcheck source=scripts/lib/oci.sh
source "$script_dir/../lib/oci.sh"
# shellcheck source=scripts/secrets/lib/files.sh
source "$script_dir/lib/files.sh"
# shellcheck source=scripts/secrets/lib/polaris.sh
source "$script_dir/lib/polaris.sh"
# shellcheck source=scripts/secrets/lib/roles.sh
source "$script_dir/lib/roles.sh"

require_role "$role" data control processing
require_command "$oci_bin" "OCI CLI not found. Install OCI CLI or set OCI_BIN before deployment."
require_command base64
if [[ "$role" == "data" ]]; then
  require_command python3
fi

secrets_dir="${VN_NEWS_SECRETS_HOST_DIR:-/run/vn-news/secrets}"
app_uid="${VN_NEWS_APP_UID:-10001}"
cloudflared_uid="${VN_NEWS_CLOUDFLARED_UID:-65532}"
cloudflared_gid="${VN_NEWS_CLOUDFLARED_GID:-65532}"
polaris_uid="${VN_NEWS_POLARIS_UID:-10000}"
polaris_gid="${VN_NEWS_POLARIS_GID:-10001}"
polaris_db_uid="${VN_NEWS_POLARIS_DB_UID:-999}"
polaris_db_gid="${VN_NEWS_POLARIS_DB_GID:-999}"
host_group="${VN_NEWS_HOST_SECRET_GROUP:-vn-news}"

install -d -m 0710 -o root -g "$host_group" "$(dirname "$secrets_dir")"
install -d -m 0710 -o root -g "$host_group" "$secrets_dir"
materialize_role
cleanup_stale_managed_secrets
echo "materialized runtime secrets for role: $role"
