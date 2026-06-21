#!/usr/bin/env bash
set -euo pipefail

action="${1:?usage: scripts/resource_manager/job.sh plan|apply <plan-job-id>|logs <job-id>}"
shift || true
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
local_resource_manager_env="${VN_NEWS_RESOURCE_MANAGER_ENV_FILE:-$repo_root/.resource-manager.env}"
oci_bin="${OCI_BIN:-oci}"

# shellcheck source=scripts/lib/common.sh
source "$script_dir/../lib/common.sh"

load_optional_env_file "$local_resource_manager_env"
require_env_var OCI_RM_STACK_OCID
require_command "$oci_bin" "OCI CLI not found. Set OCI_BIN=/path/to/oci or add oci to PATH."

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

job_id_from_payload() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["id"])'
}

job_state_from_payload() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["lifecycle-state"])'
}

print_job_logs() {
  local job_id="$1"

  "$oci_bin" resource-manager job get-job-logs \
    --job-id "$job_id" \
    --sort-order ASC \
    --all \
    --query 'data[].message' \
    --raw-output || true
}

finish_job() {
  local payload="$1"
  local job_id job_state

  job_id="$(job_id_from_payload <<<"$payload")"
  job_state="$(job_state_from_payload <<<"$payload")"
  echo "resource manager job: id=$job_id state=$job_state"
  if [[ "$job_state" != "SUCCEEDED" ]]; then
    print_job_logs "$job_id" >&2
    exit 1
  fi
  printf '%s\n' "$job_id"
}

case "$action" in
  plan)
    payload="$(
      "$oci_bin" resource-manager job create-plan-job \
        --stack-id "$OCI_RM_STACK_OCID" \
        --display-name "vn-news-plan-${timestamp}" \
        --wait-for-state SUCCEEDED \
        --wait-for-state FAILED \
        --max-wait-seconds "${OCI_RM_JOB_MAX_WAIT_SECONDS:-1800}" \
        --wait-interval-seconds "${OCI_RM_JOB_WAIT_INTERVAL_SECONDS:-15}"
    )"
    finish_job "$payload"
    ;;
  apply)
    plan_job_id="${1:?plan job id is required for apply}"
    payload="$(
      "$oci_bin" resource-manager job create-apply-job \
        --stack-id "$OCI_RM_STACK_OCID" \
        --display-name "vn-news-apply-${timestamp}" \
        --execution-plan-strategy FROM_PLAN_JOB_ID \
        --execution-plan-job-id "$plan_job_id" \
        --wait-for-state SUCCEEDED \
        --wait-for-state FAILED \
        --max-wait-seconds "${OCI_RM_JOB_MAX_WAIT_SECONDS:-2400}" \
        --wait-interval-seconds "${OCI_RM_JOB_WAIT_INTERVAL_SECONDS:-15}"
    )"
    finish_job "$payload"
    ;;
  logs)
    job_id="${1:?job id is required for logs}"
    print_job_logs "$job_id"
    ;;
  *)
    echo "Unknown Resource Manager job action: $action" >&2
    exit 2
    ;;
esac
