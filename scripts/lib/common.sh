#!/usr/bin/env bash

require_command() {
  local command_name="$1"
  local message="${2:-Missing required command: $command_name}"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$message" >&2
    exit 1
  fi
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root." >&2
    exit 1
  fi
}

require_role() {
  local role_value="$1"
  shift

  local candidate
  for candidate in "$@"; do
    if [[ "$role_value" == "$candidate" ]]; then
      return
    fi
  done

  echo "Unsupported role: $role_value (expected: $*)" >&2
  exit 2
}

require_positive_integer() {
  local value="$1"
  local label="$2"

  if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 ]]; then
    echo "$label must be a positive integer" >&2
    exit 2
  fi
}

require_readable_file() {
  local path="$1"
  local message="${2:-Missing readable file: $path}"

  if [[ ! -r "$path" ]]; then
    echo "$message" >&2
    exit 1
  fi
}

require_env_var() {
  local name="$1"

  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

load_env_file() {
  local path="$1"

  require_readable_file "$path" "Missing role configuration: $path"
  set -a
  # shellcheck disable=SC1090
  source "$path"
  set +a
}

load_optional_env_file() {
  local path="$1"

  if [[ -f "$path" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$path"
    set +a
  fi
}

role_env_path() {
  local role_value="$1"

  printf '%s\n' "${VN_NEWS_ENV_FILE:-/etc/vn-news/env/${role_value}.env}"
}

role_compose_file() {
  local role_value="$1"
  local infra_root="$2"

  case "$role_value" in
    data | control | processing)
      printf '%s/compose.%s.yaml\n' "$infra_root" "$role_value"
      ;;
    *)
      echo "Unsupported compose role: $role_value" >&2
      exit 2
      ;;
  esac
}

compose_for_role() {
  local role_value="$1"
  local env_file="$2"
  local infra_root="$3"
  shift 3

  docker compose --env-file "$env_file" -f "$(role_compose_file "$role_value" "$infra_root")" "$@"
}
