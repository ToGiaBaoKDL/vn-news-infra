#!/usr/bin/env bash
set -euo pipefail

role="${1:?role is required: data or control}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::FutureWarning}"

# shellcheck source=scripts/lib/common.sh
source "$script_dir/../lib/common.sh"
# shellcheck source=scripts/lib/oci.sh
source "$script_dir/../lib/oci.sh"

require_role "$role" data control
require_command docker
require_command grep
require_command "$oci_bin"
require_command seq
require_command sleep
require_command tar
env_file="$(role_env_path "$role")"
load_env_file "$env_file"

bucket="${VN_NEWS_RECOVERY_BUCKET:?VN_NEWS_RECOVERY_BUCKET is required}"
namespace="$(oci_command os ns get --query data --raw-output)"
tmp_dir="$(mktemp -d)"
restore_container=""

cleanup() {
  if [[ -n "$restore_container" ]]; then
    docker rm -f "$restore_container" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}

trap cleanup EXIT

latest_object() {
  local prefix="$1"

  oci_command os object list \
    --namespace-name "$namespace" \
    --bucket-name "$bucket" \
    --prefix "$prefix/" \
    --all \
    --query 'reverse(sort_by(data, &"time-created"))[0].name' \
    --raw-output
}

download_latest() {
  local prefix="$1"
  local object_name target

  object_name="$(latest_object "$prefix")"
  [[ "$object_name" != "null" && -n "$object_name" ]] || {
    echo "No recovery object found for prefix: $prefix" >&2
    exit 1
  }
  target="$tmp_dir/$(basename "$object_name")"
  oci_command os object get \
    --namespace-name "$namespace" \
    --bucket-name "$bucket" \
    --name "$object_name" \
    --file "$target" >/dev/null
  printf '%s\n' "$target"
}

verify_postgres_dump() {
  local dump_file="$1"
  local image="$2"
  local db_name="$3"
  local db_user="$4"
  local label="$5"
  local restored_tables

  restore_container="vn-news-${label}-restore-$$"
  docker run -d \
    --rm \
    --name "$restore_container" \
    --network none \
    --tmpfs /var/lib/postgresql:rw,size=512m \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    "$image" >/dev/null
  for _ in $(seq 1 30); do
    if docker exec "$restore_container" pg_isready -U postgres >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  docker exec "$restore_container" pg_isready -U postgres >/dev/null
  docker exec "$restore_container" createuser \
    --username postgres \
    --login \
    "$db_user"
  docker exec "$restore_container" createdb \
    --username postgres \
    --owner "$db_user" \
    "$db_name"
  docker exec -i "$restore_container" pg_restore \
    --username postgres \
    --dbname "$db_name" \
    --role "$db_user" \
    --no-owner \
    --no-privileges \
    --exit-on-error <"$dump_file" >/dev/null
  restored_tables="$(
    docker exec "$restore_container" psql \
      --username postgres \
      --dbname "$db_name" \
      --tuples-only \
      --no-align \
      --command "select count(*) from information_schema.tables where table_schema = 'public';"
  )"
  [[ "$restored_tables" =~ ^[1-9][0-9]*$ ]] || {
    echo "$label restore verification produced no public tables." >&2
    exit 1
  }
  docker rm -f "$restore_container" >/dev/null
  restore_container=""
}

verify_data() {
  local metadata_archive polaris_dump listing

  metadata_archive="$(download_latest redpanda-metadata)"
  polaris_dump="$(download_latest polaris-db)"
  listing="$tmp_dir/redpanda-metadata.list"
  tar -tzf "$metadata_archive" >"$listing"
  grep -q './cluster-info.txt' "$listing"
  grep -q './topics.txt' "$listing"
  verify_postgres_dump \
    "$polaris_dump" \
    "${POLARIS_DB_IMAGE:-postgres:18.3}" \
    "${VN_NEWS_POLARIS_DB_NAME:-POLARIS}" \
    "${VN_NEWS_POLARIS_DB_USER:-polaris}" \
    polaris
  echo "restore verification ok: data"
}

verify_control() {
  local airflow_dump config_archive config_listing release_archive release_listing

  airflow_dump="$(download_latest airflow-db)"
  config_archive="$(download_latest config)"
  release_archive="$(download_latest release-manifests)"
  config_listing="$tmp_dir/config.list"
  release_listing="$tmp_dir/release-manifests.list"

  verify_postgres_dump \
    "$airflow_dump" \
    "${AIRFLOW_DB_IMAGE:-postgres:16.9}" \
    airflow \
    airflow \
    airflow

  tar -tzf "$config_archive" >"$config_listing"
  tar -tzf "$release_archive" >"$release_listing"
  grep -q '^configs/settings.yaml$' "$config_listing"
  grep -q '^releases/' "$release_listing"
  echo "restore verification ok: control"
}

case "$role" in
  data) verify_data ;;
  control) verify_control ;;
esac
