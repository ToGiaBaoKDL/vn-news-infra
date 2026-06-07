#!/usr/bin/env bash
set -euo pipefail

role="${1:?role is required: data or control}"
env_file="${VN_NEWS_ENV_FILE:-/etc/vn-news/env/${role}.env}"
oci_auth="${VN_NEWS_OCI_AUTH:-instance_principal}"
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::FutureWarning}"

case "$role" in
  data | control) ;;
  *)
    echo "Unsupported restore-verification role: $role" >&2
    exit 2
    ;;
esac

for command_name in docker grep oci seq sleep tar; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done
[[ -r "$env_file" ]] || {
  echo "Missing role configuration: $env_file" >&2
  exit 1
}

set -a
source "$env_file"
set +a

bucket="${VN_NEWS_RECOVERY_BUCKET:?VN_NEWS_RECOVERY_BUCKET is required}"
namespace="$(oci os ns get --auth "$oci_auth" --query data --raw-output)"
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

  oci os object list \
    --auth "$oci_auth" \
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
  oci os object get \
    --auth "$oci_auth" \
    --namespace-name "$namespace" \
    --bucket-name "$bucket" \
    --name "$object_name" \
    --file "$target" >/dev/null
  printf '%s\n' "$target"
}

verify_data() {
  local metadata_archive listing

  metadata_archive="$(download_latest redpanda-metadata)"
  listing="$tmp_dir/redpanda-metadata.list"
  tar -tzf "$metadata_archive" >"$listing"
  grep -q './cluster-info.txt' "$listing"
  grep -q './topics.txt' "$listing"
  echo "restore verification ok: data"
}

verify_control() {
  local airflow_dump config_archive config_listing release_archive release_listing restored_tables

  airflow_dump="$(download_latest airflow-db)"
  config_archive="$(download_latest config)"
  release_archive="$(download_latest release-manifests)"
  config_listing="$tmp_dir/config.list"
  release_listing="$tmp_dir/release-manifests.list"

  restore_container="vn-news-airflow-restore-$$"
  docker run -d \
    --rm \
    --name "$restore_container" \
    --network none \
    --tmpfs /var/lib/postgresql/data:rw,size=512m \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    "${AIRFLOW_DB_IMAGE:-postgres:16.9}" >/dev/null
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
    airflow
  docker exec "$restore_container" createdb \
    --username postgres \
    --owner airflow \
    airflow
  docker exec -i "$restore_container" pg_restore \
    --username postgres \
    --dbname airflow \
    --role airflow \
    --no-owner \
    --no-privileges \
    --exit-on-error <"$airflow_dump" >/dev/null
  restored_tables="$(
    docker exec "$restore_container" psql \
      --username postgres \
      --dbname airflow \
      --tuples-only \
      --no-align \
      --command "select count(*) from information_schema.tables where table_schema = 'public';"
  )"
  [[ "$restored_tables" =~ ^[1-9][0-9]*$ ]] || {
    echo "Airflow restore verification produced no public tables." >&2
    exit 1
  }
  docker rm -f "$restore_container" >/dev/null
  restore_container=""

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
