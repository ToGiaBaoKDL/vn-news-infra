#!/usr/bin/env bash
# shellcheck disable=SC2154

log() {
  printf '[vn-news-bootstrap] %s\n' "$*"
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root, for example: sudo $0 <data|control|processing>" >&2
    exit 1
  fi
}

require_role() {
  case "$role" in
    data | control | processing) ;;
    *)
      echo "Usage: sudo $0 <data|control|processing>" >&2
      exit 1
      ;;
  esac
}

ensure_dir() {
  local path="$1"
  local mode="$2"
  local owner="$3"

  install -d -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$path"
}
