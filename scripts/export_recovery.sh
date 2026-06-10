#!/usr/bin/env bash
set -euo pipefail

role="${1:?role is required: data or control}"
deploy_root="${VN_NEWS_DEPLOY_ROOT:-$HOME/vn-news-intelligence}"
repos_root="$deploy_root/repos"
infra_root="$repos_root/vn-news-infra"
env_file="${VN_NEWS_ENV_FILE:-/etc/vn-news/env/${role}.env}"
oci_auth="${VN_NEWS_OCI_AUTH:-instance_principal}"
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::FutureWarning}"

case "$role" in
  data | control) ;;
  *)
    echo "Unsupported recovery-export role: $role" >&2
    exit 2
    ;;
esac

for command_name in docker oci tar; do
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
date_partition="$(date -u +%F)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

upload() {
  local prefix="$1"
  local file="$2"
  local object_name="${prefix}/date=${date_partition}/$(basename "$file")"

  oci os object put \
    --auth "$oci_auth" \
    --namespace-name "$namespace" \
    --bucket-name "$bucket" \
    --name "$object_name" \
    --file "$file" \
    --force >/dev/null
  oci os object head \
    --auth "$oci_auth" \
    --namespace-name "$namespace" \
    --bucket-name "$bucket" \
    --name "$object_name" >/dev/null
  echo "uploaded recovery object: $object_name"
}

export_release_identity() {
  local artifact="$tmp_dir/release-identity-${timestamp}.txt"

  printf 'release_tag=%s\nimage_tag=%s\n' \
    "${VN_NEWS_RELEASE_TAG:?VN_NEWS_RELEASE_TAG is required}" \
    "${VN_NEWS_IMAGE_TAG:?VN_NEWS_IMAGE_TAG is required}" \
    >"$artifact"
  upload release-identity "$artifact"
}

export_data() {
  local metadata_dir="$tmp_dir/redpanda-metadata"
  local artifact="$tmp_dir/redpanda-metadata-${timestamp}.tar.gz"

  install -d "$metadata_dir"
  docker compose --env-file "$env_file" -f "$infra_root/compose.data.yaml" \
    exec -T redpanda rpk cluster info -X brokers=localhost:9092 >"$metadata_dir/cluster-info.txt"
  docker compose --env-file "$env_file" -f "$infra_root/compose.data.yaml" \
    exec -T redpanda rpk topic list -X brokers=localhost:9092 >"$metadata_dir/topics.txt"
  docker compose --env-file "$env_file" -f "$infra_root/compose.data.yaml" \
    exec -T redpanda rpk cluster config get auto_create_topics_enabled \
    >"$metadata_dir/auto-create-topics.txt"
  tar -C "$metadata_dir" -czf "$artifact" .
  upload redpanda-metadata "$artifact"
}

export_control() {
  local airflow_dump="$tmp_dir/airflow-${timestamp}.dump"
  local config_archive="$tmp_dir/config-${timestamp}.tar.gz"
  local release_archive="$tmp_dir/release-manifests-${timestamp}.tar.gz"

  docker compose --env-file "$env_file" -f "$infra_root/compose.control.yaml" \
    exec -T airflow-db pg_dump \
    --username airflow \
    --dbname airflow \
    --format custom \
    --no-owner \
    --no-privileges >"$airflow_dump"
  tar -C "$repos_root/vn-news-config" -czf "$config_archive" configs
  tar -C "$repos_root/vn-news-cicd" -czf "$release_archive" releases

  upload airflow-db "$airflow_dump"
  upload config "$config_archive"
  upload release-manifests "$release_archive"
}

case "$role" in
  data)
    export_release_identity
    export_data
    ;;
  control)
    export_release_identity
    export_control
    ;;
esac
