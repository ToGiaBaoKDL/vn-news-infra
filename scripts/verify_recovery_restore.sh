#!/usr/bin/env bash
set -euo pipefail

role="${1:?role is required: data or control}"
deploy_root="${VN_NEWS_DEPLOY_ROOT:-/home/ubuntu/vn-news-intelligence}"
repos_root="$deploy_root/repos"
infra_root="$repos_root/vn-news-infra"
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

for command_name in docker grep oci tar; do
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
trap 'rm -rf "$tmp_dir"' EXIT

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
  local airflow_dump config_archive config_listing release_archive release_listing

  airflow_dump="$(download_latest airflow-db)"
  config_archive="$(download_latest config)"
  release_archive="$(download_latest release-manifests)"
  config_listing="$tmp_dir/config.list"
  release_listing="$tmp_dir/release-manifests.list"

  docker compose --env-file "$env_file" -f "$infra_root/compose.control.yaml" \
    exec -T airflow-db pg_restore --list <"$airflow_dump" >/dev/null
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
