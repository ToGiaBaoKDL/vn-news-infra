#!/usr/bin/env bash
set -euo pipefail

role="${1:?usage: scripts/host/reset_role.sh <data|control|processing> --wipe-data --force}"
shift
wipe_data=0
force=0
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
repos_root="$(cd "$repo_root/.." && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$script_dir/../lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/host/reset_role.sh <data|control|processing> --wipe-data --force

Stops Docker Compose services for a role and removes that role's persistent
service data under /srv/vn-news-*. Runtime secrets and host env files are kept.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wipe-data)
      wipe_data=1
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_role "$role" data control processing
require_root
require_command docker
if [[ "$wipe_data" -ne 1 || "$force" -ne 1 ]]; then
  echo "Refusing destructive reset without --wipe-data --force." >&2
  exit 2
fi

env_file="$(role_env_path "$role")"
load_env_file "$env_file"

compose_down() {
  local compose_file="$1"

  if [[ -f "$compose_file" ]]; then
    docker compose --env-file "$env_file" -f "$compose_file" down --remove-orphans --volumes
  fi
}

assert_wipe_path() {
  local path="$1"

  if [[ -z "$path" || "$path" == "/" || "$path" != /srv/vn-news-*/* ]]; then
    echo "Refusing to wipe unexpected path: $path" >&2
    exit 1
  fi
}

wipe_path() {
  local path="$1"

  assert_wipe_path "$path"
  if [[ -e "$path" ]]; then
    rm -rf --one-file-system "$path"
    echo "wiped: $path"
  else
    echo "absent: $path"
  fi
}

compose_down "$repo_root/compose.${role}.yaml"

case "$role" in
  data)
    data_root="${VN_NEWS_DATA_ROOT:?VN_NEWS_DATA_ROOT is required}"
    wipe_path "$data_root/redpanda"
    wipe_path "$data_root/seaweedfs"
    wipe_path "$data_root/polaris-postgres"
    ;;
  control)
    app_compose="$repos_root/vn-news-app/compose.yaml"
    compose_down "$app_compose"
    wipe_path "${VN_NEWS_AIRFLOW_DB_DIR:-/srv/vn-news-control/airflow-db}"
    wipe_path "${VN_NEWS_AIRFLOW_LOGS_DIR:-/srv/vn-news-control/airflow-logs}"
    wipe_path "${VN_NEWS_AIRFLOW_DAG_BUNDLES_DIR:-/srv/vn-news-control/airflow-dag-bundles}"
    wipe_path "${VN_NEWS_SPARK_CHECKPOINT_ROOT:-/srv/vn-news-control/spark/checkpoints}"
    ;;
  processing)
    wipe_path "${VN_NEWS_SPARK_WORKER_DIR:-/srv/vn-news-processing/spark/work}"
    wipe_path "${VN_NEWS_SPARK_LOCAL_DIR:-/srv/vn-news-processing/spark/local}"
    ;;
esac

echo "reset role state: $role"
