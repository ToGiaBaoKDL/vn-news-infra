#!/usr/bin/env bash
set -euo pipefail

retention_hours="${VN_NEWS_TASK_CONTAINER_RETENTION_HOURS:-24}"
execute=0

usage() {
  cat <<'EOF'
Usage: scripts/prune_airflow_task_containers.sh [options]

Options:
  --older-than-hours HOURS  Remove stopped task containers older than HOURS.
                            Defaults to VN_NEWS_TASK_CONTAINER_RETENTION_HOURS or 24.
  --execute                 Remove containers. Without this, print a dry run.
  --dry-run                 Print candidates only.
  -h, --help                Show this help.

Only stopped containers are considered. The script targets VN News Airflow task
containers by Docker labels and falls back to the legacy feed-ingestor name
prefix for containers created before labels were added.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --older-than-hours)
      retention_hours="${2:?missing value for --older-than-hours}"
      shift 2
      ;;
    --execute)
      execute=1
      shift
      ;;
    --dry-run)
      execute=0
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

if ! [[ "$retention_hours" =~ ^[0-9]+$ ]] || [[ "$retention_hours" -lt 1 ]]; then
  echo "--older-than-hours must be a positive integer" >&2
  exit 2
fi

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required" >&2
    exit 1
  fi
}

candidate_ids() {
  local status="$1"

  docker container ls -a \
    --filter "status=$status" \
    --filter "label=com.tgbao.vn-news.managed-by=airflow" \
    --filter "label=com.tgbao.vn-news.service=feed-ingestor" \
    --format '{{.ID}}'

  docker container ls -a \
    --filter "status=$status" \
    --filter "name=vn-news-feed-ingestor-" \
    --format '{{.ID}}'
}

require_command docker
require_command date

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not reachable. Run this on the Airflow control host with Docker access." >&2
  exit 1
fi

now_epoch="$(date -u +%s)"
max_age_seconds=$((retention_hours * 3600))
declare -A seen=()
pruned_count=0
candidate_count=0

for status in created exited dead; do
  while IFS= read -r container_id; do
    [[ -n "$container_id" ]] || continue
    if [[ -n "${seen[$container_id]:-}" ]]; then
      continue
    fi
    seen["$container_id"]=1
    candidate_count=$((candidate_count + 1))

    inspect_line="$(
      docker inspect \
        --format '{{.Created}}|{{.State.Status}}|{{.Name}}|{{.Config.Image}}' \
        "$container_id"
    )"
    IFS='|' read -r created_at current_status container_name image_name <<<"$inspect_line"
    created_epoch="$(date -u -d "$created_at" +%s)"
    age_seconds=$((now_epoch - created_epoch))
    if [[ "$age_seconds" -lt "$max_age_seconds" ]]; then
      continue
    fi

    container_name="${container_name#/}"
    if [[ "$execute" -eq 1 ]]; then
      docker rm "$container_id" >/dev/null
      printf 'removed %s status=%s age_hours=%s image=%s\n' \
        "$container_name" "$current_status" "$((age_seconds / 3600))" "$image_name"
    else
      printf 'would_remove %s status=%s age_hours=%s image=%s\n' \
        "$container_name" "$current_status" "$((age_seconds / 3600))" "$image_name"
    fi
    pruned_count=$((pruned_count + 1))
  done < <(candidate_ids "$status")
done

if [[ "$execute" -eq 1 ]]; then
  printf 'airflow task container cleanup complete: removed=%s candidates=%s retention_hours=%s\n' \
    "$pruned_count" "$candidate_count" "$retention_hours"
else
  printf 'airflow task container cleanup dry-run: removable=%s candidates=%s retention_hours=%s\n' \
    "$pruned_count" "$candidate_count" "$retention_hours"
fi
