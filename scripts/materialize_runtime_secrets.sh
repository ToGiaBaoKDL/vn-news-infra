#!/usr/bin/env bash
set -euo pipefail

role="${1:?role is required: data, control, or processing}"
secrets_dir="${VN_NEWS_SECRETS_HOST_DIR:-/run/vn-news/secrets}"
oci_bin="${OCI_BIN:-oci}"
oci_auth="${VN_NEWS_OCI_AUTH:-instance_principal}"
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::FutureWarning}"

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
        seaweedfs-s3.json \
        0400 \
        "${VN_NEWS_SEAWEEDFS_UID:-1000}:${VN_NEWS_SEAWEEDFS_GID:-1000}"
      ;;
    control)
      write_secret_file VN_NEWS_INGESTION_S3_SECRET_OCID ingestion-s3-credentials
      write_secret_file VN_NEWS_AIRFLOW_DB_PASSWORD_SECRET_OCID airflow-db-password
      write_secret_file VN_NEWS_AIRFLOW_JWT_SECRET_OCID airflow-api-jwt-secret
      write_secret_file VN_NEWS_AIRFLOW_FERNET_KEY_SECRET_OCID airflow-fernet-key
      write_secret_file VN_NEWS_AIRFLOW_ADMIN_PASSWORD_SECRET_OCID airflow-admin-password
      ;;
    processing)
      write_secret_file VN_NEWS_INGESTION_S3_SECRET_OCID ingestion-s3-credentials
      ;;
    *)
      echo "Unknown role: $role" >&2
      exit 1
      ;;
  esac
}

require_oci_cli
install -d -m 0700 "$secrets_dir"
materialize_role
echo "materialized runtime secrets for role: $role"
