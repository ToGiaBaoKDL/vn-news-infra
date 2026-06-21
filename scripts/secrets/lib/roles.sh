#!/usr/bin/env bash
# shellcheck disable=SC2154

role_file_specs() {
  local role_value="$1"

  case "$role_value" in
    data)
      printf '%s|%s|%s|%s|%s\n' \
        secret VN_NEWS_SEAWEEDFS_S3_CONFIG_SECRET_OCID seaweedfs-s3-config.json 0400 "${VN_NEWS_SEAWEEDFS_UID:-1000}:${VN_NEWS_SEAWEEDFS_GID:-1000}" \
        secret VN_NEWS_STORAGE_ADMIN_S3_CREDENTIALS_SECRET_OCID storage-admin-s3-credentials 0440 "root:$host_group" \
        secret VN_NEWS_POLARIS_DB_PASSWORD_SECRET_OCID polaris-db-password 0400 "$polaris_db_uid:$polaris_db_gid" \
        generated "" "$polaris_application_properties_file" 0400 "$polaris_uid:$polaris_gid" \
        generated "" "$polaris_bootstrap_credentials_file" 0400 "$polaris_uid:$polaris_gid" \
        secret VN_NEWS_CLOUDFLARE_DATA_TUNNEL_TOKEN_SECRET_OCID cloudflare-data-tunnel-token 0400 "$cloudflared_uid:$cloudflared_gid"
      ;;
    control)
      printf '%s|%s|%s|%s|%s\n' \
        secret VN_NEWS_INGESTION_S3_CREDENTIALS_SECRET_OCID ingestion-s3-credentials 0440 "$app_uid:$host_group" \
        secret VN_NEWS_POLARIS_CLIENT_CREDENTIALS_SECRET_OCID polaris-client-credentials.json 0440 "${VN_NEWS_AIRFLOW_UID:-50000}:${VN_NEWS_AIRFLOW_GID:-0}" \
        secret VN_NEWS_SPARK_RPC_AUTH_SECRET_OCID spark-rpc-auth-secret 0440 root:root \
        secret VN_NEWS_AIRFLOW_DB_PASSWORD_SECRET_OCID airflow-db-password 0440 root:root \
        secret VN_NEWS_AIRFLOW_API_JWT_SECRET_OCID airflow-api-jwt-secret 0440 root:root \
        secret VN_NEWS_AIRFLOW_FERNET_KEY_SECRET_OCID airflow-fernet-key 0440 root:root \
        secret VN_NEWS_AIRFLOW_ADMIN_PASSWORD_SECRET_OCID airflow-admin-password 0440 root:root \
        secret VN_NEWS_CLOUDFLARE_CONTROL_TUNNEL_TOKEN_SECRET_OCID cloudflare-control-tunnel-token 0400 "$cloudflared_uid:$cloudflared_gid"
      ;;
    processing)
      printf '%s|%s|%s|%s|%s\n' \
        secret VN_NEWS_INGESTION_S3_CREDENTIALS_SECRET_OCID ingestion-s3-credentials 0440 "$app_uid:$host_group" \
        secret VN_NEWS_SPARK_RPC_AUTH_SECRET_OCID spark-rpc-auth-secret 0440 root:root
      ;;
    *)
      echo "Unknown role: $role_value" >&2
      exit 1
      ;;
  esac
}

materialize_role() {
  local kind env_name target_name file_mode file_owner

  while IFS='|' read -r kind env_name target_name file_mode file_owner; do
    case "$kind" in
      secret)
        write_secret_file "$env_name" "$target_name" "$file_mode" "$file_owner"
        ;;
      generated)
        ;;
      *)
        echo "Unknown managed secret spec type: $kind" >&2
        exit 1
        ;;
    esac
  done < <(role_file_specs "$role")

  if [[ "$role" == "data" ]]; then
    render_polaris_runtime_files
  fi
}

allowed_secret_files_for_role() {
  local role_value="$1"
  local target_name

  while IFS='|' read -r _ _ target_name _ _; do
    printf '%s\n' "$target_name"
  done < <(role_file_specs "$role_value")
}

allowed_secret_files() {
  allowed_secret_files_for_role "$role"
}

managed_secret_files() {
  {
    allowed_secret_files_for_role data
    allowed_secret_files_for_role control
    allowed_secret_files_for_role processing
  } | sort -u
}

cleanup_stale_managed_secrets() {
  local allowed managed_file managed_path
  allowed="$(allowed_secret_files)"

  while IFS= read -r managed_file; do
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
  done < <(managed_secret_files)
}
