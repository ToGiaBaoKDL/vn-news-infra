#!/usr/bin/env bash
set -euo pipefail

credential="${1:-}"
control_host="${VN_NEWS_CONTROL_SSH_HOST:-tgb-control-1}"
data_host="${VN_NEWS_DATA_SSH_HOST:-tgb-data-1}"
processing_host="${VN_NEWS_PROCESSING_SSH_HOST:-tgb-processing-1}"

usage() {
  cat <<'EOF'
Usage: scripts/get_service_credential.sh <credential>

Credentials:
  airflow-admin-password
  airflow-db-password
  seaweedfs-storage-admin
  seaweedfs-ingestion
  seaweedfs-curated-writer
EOF
}

case "$credential" in
  airflow-admin-password)
    host="$control_host"
    secret_file="airflow-admin-password"
    ;;
  airflow-db-password)
    host="$control_host"
    secret_file="airflow-db-password"
    ;;
  seaweedfs-storage-admin)
    host="$data_host"
    secret_file="storage-admin-s3-credentials"
    ;;
  seaweedfs-ingestion)
    host="$control_host"
    secret_file="ingestion-s3-credentials"
    ;;
  seaweedfs-curated-writer)
    host="$processing_host"
    secret_file="curated-writer-s3-credentials"
    ;;
  -h | --help | "")
    usage
    exit 0
    ;;
  *)
    echo "Unknown credential: $credential" >&2
    usage >&2
    exit 2
    ;;
esac

exec ssh "$host" sudo cat "/run/vn-news/secrets/$secret_file"
