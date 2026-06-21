#!/usr/bin/env bash
set -euo pipefail

role="${1:?role is required: data or control}"
deploy_root="${2:?deploy root is required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
recovery_dir="$(cd "$script_dir/../recovery" && pwd)"
shared_lib_dir="$(cd "$script_dir/../lib" && pwd)"
install_root="/usr/local/lib/vn-news"

# shellcheck source=scripts/lib/common.sh
source "$shared_lib_dir/common.sh"

require_root
require_role "$role" data control

install -d -m 0755 "$install_root/host" "$install_root/lib" "$install_root/recovery"
install -m 0755 "$recovery_dir/export.sh" "$install_root/recovery/export.sh"
install -m 0755 "$recovery_dir/verify.sh" "$install_root/recovery/verify.sh"
install -m 0755 "$script_dir/publish_metrics.sh" "$install_root/host/publish_metrics.sh"
install -m 0644 "$shared_lib_dir/common.sh" "$install_root/lib/common.sh"
install -m 0644 "$shared_lib_dir/oci.sh" "$install_root/lib/oci.sh"

cat >/etc/systemd/system/vn-news-recovery-export@.service <<EOF
[Unit]
Description=VN News recovery export for %i
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=VN_NEWS_DEPLOY_ROOT=$deploy_root
ExecStart=$install_root/recovery/export.sh %i
TimeoutStartSec=30m
EOF

cat >/etc/systemd/system/vn-news-recovery-export@.timer <<'EOF'
[Unit]
Description=Daily VN News recovery export for %i

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=45m
Unit=vn-news-recovery-export@%i.service

[Install]
WantedBy=timers.target
EOF

if [[ "$role" == "data" ]]; then
  cat >/etc/systemd/system/vn-news-data-volume-metric.service <<EOF
[Unit]
Description=Publish VN News data-volume capacity metric
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$install_root/host/publish_metrics.sh
TimeoutStartSec=2m
EOF

  cat >/etc/systemd/system/vn-news-data-volume-metric.timer <<'EOF'
[Unit]
Description=Publish VN News data-volume capacity metric every fifteen minutes

[Timer]
OnBootSec=5m
OnUnitActiveSec=15m
Persistent=true

[Install]
WantedBy=timers.target
EOF
fi

systemctl daemon-reload
systemctl enable --now "vn-news-recovery-export@${role}.timer"
systemctl is-enabled --quiet "vn-news-recovery-export@${role}.timer"
if [[ "$role" == "data" ]]; then
  systemctl enable --now vn-news-data-volume-metric.timer
  systemctl is-enabled --quiet vn-news-data-volume-metric.timer
fi
echo "configured host operations: $role"
