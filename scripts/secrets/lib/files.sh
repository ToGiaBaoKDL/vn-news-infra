#!/usr/bin/env bash
# shellcheck disable=SC2154

read_secret_content() {
  local env_name="$1"
  local secret_id="${!env_name:-}"

  if [[ -z "$secret_id" ]]; then
    echo "Missing required environment variable: $env_name" >&2
    exit 1
  fi
  oci_command secrets secret-bundle get \
    --secret-id "$secret_id" \
    --query 'data."secret-bundle-content".content' \
    --raw-output \
    | base64 --decode
}

assert_managed_target() {
  local target_name="$1"
  local target_path="$secrets_dir/$target_name"

  if [[ -e "$target_path" && ! -f "$target_path" && ! -L "$target_path" ]]; then
    echo "Refusing to replace non-file runtime secret path: $target_path" >&2
    exit 1
  fi
}

finalize_managed_file() {
  local tmp_path="$1"
  local target_name="$2"
  local file_mode="$3"
  local file_owner="$4"
  local target_path="$secrets_dir/$target_name"

  chmod "$file_mode" "$tmp_path"
  chown "$file_owner" "$tmp_path"
  mv "$tmp_path" "$target_path"
  chown "$file_owner" "$target_path"
  chmod "$file_mode" "$target_path"
}

write_managed_file() {
  local target_name="$1"
  local file_mode="$2"
  local file_owner="$3"
  local tmp_path

  assert_managed_target "$target_name"
  tmp_path="$(mktemp "$secrets_dir/.${target_name}.XXXXXX")"
  chmod 0600 "$tmp_path"
  cat >"$tmp_path"
  finalize_managed_file "$tmp_path" "$target_name" "$file_mode" "$file_owner"
}

write_secret_file() {
  local env_name="$1"
  local target_name="$2"
  local file_mode="${3:-0600}"
  local file_owner="${4:-root:root}"
  local tmp_path

  assert_managed_target "$target_name"
  tmp_path="$(mktemp "$secrets_dir/.${target_name}.XXXXXX")"
  chmod 0600 "$tmp_path"
  if ! read_secret_content "$env_name" >"$tmp_path"; then
    rm -f "$tmp_path"
    return 1
  fi
  finalize_managed_file "$tmp_path" "$target_name" "$file_mode" "$file_owner"
}

read_secret_value() {
  read_secret_content "$1" | tr -d '\n\r'
}
