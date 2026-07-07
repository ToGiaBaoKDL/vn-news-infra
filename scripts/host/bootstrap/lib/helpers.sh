#!/usr/bin/env bash

log() {
  printf '[vn-news-bootstrap] %s\n' "$*"
}

ensure_dir() {
  local path="$1"
  local mode="$2"
  local owner="$3"

  install -d -m "$mode" -o "${owner%%:*}" -g "${owner##*:}" "$path"
}
