#!/usr/bin/env bash
set -euo pipefail

role="${1:?role is required: data, control, or processing}"
secrets_dir="${VN_NEWS_SECRETS_HOST_DIR:-/run/vn-news/secrets}"
oci_bin="${OCI_BIN:-oci}"
oci_auth="${VN_NEWS_OCI_AUTH:-instance_principal}"
app_uid="${VN_NEWS_APP_UID:-10001}"
cloudflared_uid="${VN_NEWS_CLOUDFLARED_UID:-65532}"
cloudflared_gid="${VN_NEWS_CLOUDFLARED_GID:-65532}"
host_group="${VN_NEWS_HOST_SECRET_GROUP:-vn-news}"
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::FutureWarning}"

managed_secret_files=(
  airflow-admin-password
  airflow-api-jwt-secret
  airflow-db-password
  airflow-fernet-key
  cloudflare-control-tunnel-token
  cloudflare-data-tunnel-token
  curated-writer-s3-credentials
  ingestion-s3-credentials
  seaweedfs-s3-config.json
  storage-admin-s3-credentials
)

require_oci_cli() {
  if ! command -v "$oci_bin" >/dev/null 2>&1; then
    echo "OCI CLI not found. Install OCI CLI or set OCI_BIN before deployment." >&2
    exit 1
  fi
}

oci_auth_args() {
  if [[ "$oci_auth" == "default" ]]; then
    return
  fi
  printf '%s\n' "--auth" "$oci_auth"
}

write_secret_file() {
  local env_name="$1"
  local target_name="$2"
  local file_mode="${3:-0600}"
  local file_owner="${4:-root:root}"
  local secret_id="${!env_name:-}"
  local target_path="$secrets_dir/$target_name"
  local tmp_path

  if [[ -z "$secret_id" ]]; then
    echo "Missing required environment variable: $env_name" >&2
    exit 1
  fi
  if [[ -e "$target_path" && ! -f "$target_path" && ! -L "$target_path" ]]; then
    echo "Refusing to replace non-file runtime secret path: $target_path" >&2
    exit 1
  fi

  tmp_path="$(mktemp "$secrets_dir/.${target_name}.XXXXXX")"
  chmod 0600 "$tmp_path"

  "$oci_bin" secrets secret-bundle get \
    $(oci_auth_args) \
    --secret-id "$secret_id" \
    --query 'data."secret-bundle-content".content' \
    --raw-output \
    | base64 --decode >"$tmp_path"

  chmod "$file_mode" "$tmp_path"
  chown "$file_owner" "$tmp_path"
  mv "$tmp_path" "$target_path"
  chown "$file_owner" "$target_path"
  chmod "$file_mode" "$target_path"
}

materialize_role() {
  case "$role" in
    data)
      write_secret_file \
        VN_NEWS_SEAWEEDFS_S3_CONFIG_SECRET_OCID \
        seaweedfs-s3-config.json \
        0400 \
        "${VN_NEWS_SEAWEEDFS_UID:-1000}:${VN_NEWS_SEAWEEDFS_GID:-1000}"
      write_secret_file VN_NEWS_STORAGE_ADMIN_S3_CREDENTIALS_SECRET_OCID storage-admin-s3-credentials 0440 "root:$host_group"
      write_secret_file VN_NEWS_CLOUDFLARE_DATA_TUNNEL_TOKEN_SECRET_OCID cloudflare-data-tunnel-token 0400 "$cloudflared_uid:$cloudflared_gid"
      ;;
    control)
      write_secret_file VN_NEWS_INGESTION_S3_CREDENTIALS_SECRET_OCID ingestion-s3-credentials 0440 "$app_uid:$host_group"
      write_secret_file VN_NEWS_AIRFLOW_DB_PASSWORD_SECRET_OCID airflow-db-password 0440 root:root
      write_secret_file VN_NEWS_AIRFLOW_API_JWT_SECRET_OCID airflow-api-jwt-secret 0440 root:root
      write_secret_file VN_NEWS_AIRFLOW_FERNET_KEY_SECRET_OCID airflow-fernet-key 0440 root:root
      write_secret_file VN_NEWS_AIRFLOW_ADMIN_PASSWORD_SECRET_OCID airflow-admin-password 0440 root:root
      write_secret_file VN_NEWS_CLOUDFLARE_CONTROL_TUNNEL_TOKEN_SECRET_OCID cloudflare-control-tunnel-token 0400 "$cloudflared_uid:$cloudflared_gid"
      ;;
    processing)
      write_secret_file VN_NEWS_INGESTION_S3_CREDENTIALS_SECRET_OCID ingestion-s3-credentials 0440 "$app_uid:$host_group"
      write_secret_file VN_NEWS_CURATED_WRITER_S3_CREDENTIALS_SECRET_OCID curated-writer-s3-credentials 0440 "$app_uid:$host_group"
      ;;
    *)
      echo "Unknown role: $role" >&2
      exit 1
      ;;
  esac
}

allowed_secret_files() {
  case "$role" in
    data)
      printf '%s\n' \
        seaweedfs-s3-config.json \
        storage-admin-s3-credentials \
        cloudflare-data-tunnel-token
      ;;
    control)
      printf '%s\n' \
        ingestion-s3-credentials \
        airflow-db-password \
        airflow-api-jwt-secret \
        airflow-fernet-key \
        airflow-admin-password \
        cloudflare-control-tunnel-token
      ;;
    processing)
      printf '%s\n' \
        ingestion-s3-credentials \
        curated-writer-s3-credentials
      ;;
    *)
      echo "Unknown role: $role" >&2
      exit 1
      ;;
  esac
}

cleanup_stale_managed_secrets() {
  local managed_file managed_path
  local allowed="$(allowed_secret_files)"

  for managed_file in "${managed_secret_files[@]}"; do
    if grep -Fxq "$managed_file" <<<"$allowed"; then
      continue
    fi
    managed_path="$secrets_dir/$managed_file"
    if [[ -e "$managed_path" ]]; then
      if [[ ! -f "$managed_path" && ! -L "$managed_path" ]]; then
        echo "Refusing to remove non-file runtime secret path: $managed_path" >&2
        exit 1
      fi
      rm -f "$managed_path"
      echo "removed stale runtime secret for role $role: $managed_file"
    fi
  done
}

require_oci_cli
install -d -m 0710 -o root -g "$host_group" "$(dirname "$secrets_dir")"
install -d -m 0710 -o root -g "$host_group" "$secrets_dir"
materialize_role
cleanup_stale_managed_secrets
echo "materialized runtime secrets for role: $role"
