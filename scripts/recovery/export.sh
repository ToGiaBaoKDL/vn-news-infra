#!/usr/bin/env bash
set -euo pipefail

role="${1:?role is required: data or control}"
deploy_root="${VN_NEWS_DEPLOY_ROOT:-$HOME/vn-news-intelligence}"
repos_root="$deploy_root/repos"
infra_root="$repos_root/vn-news-infra"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::FutureWarning}"

# shellcheck source=scripts/lib/common.sh
source "$script_dir/../lib/common.sh"
# shellcheck source=scripts/lib/oci.sh
source "$script_dir/../lib/oci.sh"

require_role "$role" data control
require_command docker
require_command "$oci_bin"
require_command tar
env_file="$(role_env_path "$role")"
load_env_file "$env_file"

bucket="${VN_NEWS_RECOVERY_BUCKET:?VN_NEWS_RECOVERY_BUCKET is required}"
namespace="$(oci_command os ns get --query data --raw-output)"
date_partition="$(date -u +%F)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

upload() {
  local prefix="$1"
  local file="$2"
  local object_name

  object_name="${prefix}/date=${date_partition}/$(basename "$file")"

  oci_command os object put \
    --namespace-name "$namespace" \
    --bucket-name "$bucket" \
    --name "$object_name" \
    --file "$file" \
    --force >/dev/null
  oci_command os object head \
    --namespace-name "$namespace" \
    --bucket-name "$bucket" \
    --name "$object_name" >/dev/null
  echo "uploaded recovery object: $object_name"
}

export_deployment_metadata() {
  local source="/etc/vn-news/deployment.json"
  local artifact="$tmp_dir/deployment-${role}-${timestamp}.json"
  local exported_at

  if [[ -f "$source" ]]; then
    cp "$source" "$artifact"
  else
    exported_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    {
      printf '{\n'
      printf '  "role": "%s",\n' "$role"
      printf '  "image_tag": "%s",\n' "${VN_NEWS_IMAGE_TAG:?VN_NEWS_IMAGE_TAG is required}"
      printf '  "exported_at": "%s",\n' "$exported_at"
      printf '  "metadata_missing": true\n'
      printf '}\n'
    } >"$artifact"
  fi
  upload "deployment-metadata/$role" "$artifact"
}

export_data() {
  local metadata_dir="$tmp_dir/redpanda-metadata"
  local artifact="$tmp_dir/redpanda-metadata-${timestamp}.tar.gz"
  local polaris_dump="$tmp_dir/polaris-${timestamp}.dump"

  install -d "$metadata_dir"
  compose_for_role data "$env_file" "$infra_root" \
    exec -T redpanda rpk cluster info -X brokers=localhost:9092 >"$metadata_dir/cluster-info.txt"
  compose_for_role data "$env_file" "$infra_root" \
    exec -T redpanda rpk topic list -X brokers=localhost:9092 >"$metadata_dir/topics.txt"
  compose_for_role data "$env_file" "$infra_root" \
    exec -T redpanda rpk cluster config get auto_create_topics_enabled \
    >"$metadata_dir/auto-create-topics.txt"
  tar -C "$metadata_dir" -czf "$artifact" .
  upload redpanda-metadata "$artifact"

  compose_for_role data "$env_file" "$infra_root" \
    exec -T polaris-db pg_dump \
    --username "${VN_NEWS_POLARIS_DB_USER:-polaris}" \
    --dbname "${VN_NEWS_POLARIS_DB_NAME:-POLARIS}" \
    --format custom \
    --no-owner \
    --no-privileges >"$polaris_dump"
  upload polaris-db "$polaris_dump"
}

export_control() {
  local airflow_dump="$tmp_dir/airflow-${timestamp}.dump"
  local config_archive="$tmp_dir/config-${timestamp}.tar.gz"

  compose_for_role control "$env_file" "$infra_root" \
    exec -T airflow-db pg_dump \
    --username airflow \
    --dbname airflow \
    --format custom \
    --no-owner \
    --no-privileges >"$airflow_dump"
  tar -C "$repos_root/vn-news-config" -czf "$config_archive" configs

  upload airflow-db "$airflow_dump"
  upload config "$config_archive"
}

case "$role" in
  data)
    export_deployment_metadata
    export_data
    ;;
  control)
    export_deployment_metadata
    export_control
    ;;
esac
