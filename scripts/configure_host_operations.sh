#!/usr/bin/env bash
set -euo pipefail

role="${1:?role is required: data or control}"
deploy_root="${2:-/home/ubuntu/vn-news-intelligence}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_root="/usr/local/lib/vn-news"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi
case "$role" in
  data | control) ;;
  *)
    echo "Unsupported operations role: $role" >&2
    exit 2
    ;;
esac

install -d -m 0755 "$install_root"
for script_name in export_recovery.sh publish_host_metrics.sh verify_recovery_restore.sh; do
  install -m 0755 "$script_dir/$script_name" "$install_root/$script_name"
done

cat >/etc/systemd/system/vn-news-recovery-export@.service <<EOF
[Unit]
Description=VN News recovery export for %i
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=VN_NEWS_DEPLOY_ROOT=$deploy_root
ExecStart=$install_root/export_recovery.sh %i
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
ExecStart=$install_root/publish_host_metrics.sh
EOF

  cat >/etc/systemd/system/vn-news-data-volume-metric.timer <<'EOF'
[Unit]
Description=Publish VN News data-volume capacity metric every five minutes

[Timer]
OnBootSec=2m
OnUnitActiveSec=5m
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
