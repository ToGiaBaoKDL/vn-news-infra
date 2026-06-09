#!/usr/bin/env bash
set -euo pipefail

credential="${1:-}"
control_host="${VN_NEWS_CONTROL_SSH_HOST:-tgb-control-1}"

usage() {
  cat <<'EOF'
Usage: scripts/get_service_credential.sh <credential>

Credentials:
  airflow-admin-password
  airflow-db-password
  seaweedfs-storage-admin
  seaweedfs-ingestion
EOF
}

case "$credential" in
  airflow-admin-password)
    secret_file="airflow-admin-password"
    ;;
  airflow-db-password)
    secret_file="airflow-db-password"
    ;;
  seaweedfs-storage-admin)
    secret_file="storage-admin-s3-credentials"
    ;;
  seaweedfs-ingestion)
    secret_file="ingestion-s3-credentials"
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

exec ssh "$control_host" sudo cat "/run/vn-news/secrets/$secret_file"
