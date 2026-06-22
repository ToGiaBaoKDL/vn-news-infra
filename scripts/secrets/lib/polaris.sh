#!/usr/bin/env bash
# shellcheck disable=SC2154

polaris_application_properties_file="polaris-application.properties"
polaris_bootstrap_credentials_file="polaris-bootstrap-credentials.json"

read_single_line_secret() {
  local secret_name="$1"
  local secret_value

  secret_value="$(tr -d '\n\r' <"$secrets_dir/$secret_name")"
  if [[ -z "$secret_value" ]]; then
    echo "Runtime secret is empty: $secret_name" >&2
    exit 1
  fi
  printf '%s' "$secret_value"
}

require_safe_identifier() {
  local name="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "$name must contain only letters, numbers, dot, underscore, or hyphen." >&2
    exit 1
  fi
}

render_polaris_runtime_files() {
  local db_password bootstrap_secret bootstrap_json realm client_id

  db_password="$(read_single_line_secret polaris-db-password)"
  bootstrap_secret="$(read_secret_value VN_NEWS_POLARIS_BOOTSTRAP_ADMIN_SECRET_OCID)"
  realm="${VN_NEWS_POLARIS_REALM:-POLARIS}"
  client_id="${VN_NEWS_POLARIS_BOOTSTRAP_CLIENT_ID:-vn-news-polaris-admin}"

  if [[ ! "$db_password" =~ ^[A-Za-z0-9]+$ ]]; then
    echo "Polaris DB password must be alphanumeric for Quarkus properties ingestion." >&2
    exit 1
  fi
  require_safe_identifier VN_NEWS_POLARIS_REALM "$realm"
  require_safe_identifier VN_NEWS_POLARIS_BOOTSTRAP_CLIENT_ID "$client_id"

  printf 'quarkus.datasource.password=%s\n' "$db_password" \
    | write_managed_file "$polaris_application_properties_file" 0400 "$polaris_uid:$polaris_gid"

  bootstrap_json="$(VN_NEWS_POLARIS_REALM="$realm" \
    VN_NEWS_POLARIS_BOOTSTRAP_CLIENT_ID="$client_id" \
    VN_NEWS_POLARIS_BOOTSTRAP_CLIENT_SECRET="$bootstrap_secret" \
    python3 -c '
import json
import os

realm = os.environ["VN_NEWS_POLARIS_REALM"]
client_id = os.environ["VN_NEWS_POLARIS_BOOTSTRAP_CLIENT_ID"]
client_secret = os.environ["VN_NEWS_POLARIS_BOOTSTRAP_CLIENT_SECRET"]
print(json.dumps({realm: {"client-id": client_id, "client-secret": client_secret}}, separators=(",", ":")))
')"
  printf '%s\n' "$bootstrap_json" \
    | write_managed_file "$polaris_bootstrap_credentials_file" 0440 "$polaris_uid:$host_group"
}
