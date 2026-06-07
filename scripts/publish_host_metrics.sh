#!/usr/bin/env bash
set -euo pipefail

mount_path="${VN_NEWS_DATA_MOUNT_PATH:-/srv/vn-news-data}"
oci_auth="${VN_NEWS_OCI_AUTH:-instance_principal}"
export PYTHONWARNINGS="${PYTHONWARNINGS:-ignore::FutureWarning}"

for command_name in curl df mountpoint oci python3; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done
mountpoint -q "$mount_path" || {
  echo "Data mount is unavailable: $mount_path" >&2
  exit 1
}

metadata_file="$(mktemp)"
metric_file="$(mktemp)"
trap 'rm -f "$metadata_file" "$metric_file"' EXIT

curl -fsS \
  -H "Authorization: Bearer Oracle" \
  http://169.254.169.254/opc/v2/instance/ >"$metadata_file"
utilization="$(df -P "$mount_path" | awk 'NR == 2 {gsub("%", "", $5); print $5}')"

python3 - "$metadata_file" "$metric_file" "$mount_path" "$utilization" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import UTC, datetime
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
payload = [
    {
        "compartmentId": metadata["compartmentId"],
        "datapoints": [
            {
                "count": 1,
                "timestamp": datetime.now(UTC).isoformat(),
                "value": float(sys.argv[4]),
            }
        ],
        "dimensions": {
            "mountPath": sys.argv[3],
            "resourceId": metadata["id"],
        },
        "metadata": {"unit": "percent"},
        "name": "DataVolumeUtilization",
        "namespace": "vn_news",
    }
]
Path(sys.argv[2]).write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
PY
region="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["region"])' "$metadata_file")"

oci monitoring metric-data post \
  --auth "$oci_auth" \
  --endpoint "https://telemetry-ingestion.${region}.oraclecloud.com" \
  --metric-data "file://$metric_file" \
  --batch-atomicity ATOMIC >/dev/null
echo "published DataVolumeUtilization=${utilization}"
