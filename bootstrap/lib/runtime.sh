#!/usr/bin/env bash
# shellcheck disable=SC2154

configure_runtime_dirs() {
  log "Creating runtime directories"
  ensure_dir /etc/vn-news 0750 root:vn-news
  ensure_dir /etc/vn-news/env 0750 root:vn-news

  cat >/etc/tmpfiles.d/vn-news.conf <<'EOF'
d /run/vn-news 0710 root vn-news -
d /run/vn-news/secrets 0710 root vn-news -
EOF
  systemd-tmpfiles --create /etc/tmpfiles.d/vn-news.conf

  ensure_dir /run/vn-news 0710 root:vn-news
  ensure_dir /run/vn-news/secrets 0710 root:vn-news

  local role_env="/etc/vn-news/env/${role}.env"
  if [[ ! -f "$role_env" ]]; then
    touch "$role_env"
  fi
  chown root:vn-news "$role_env"
  chmod 0640 "$role_env"
}
