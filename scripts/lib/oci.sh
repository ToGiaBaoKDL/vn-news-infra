#!/usr/bin/env bash

oci_bin="${oci_bin:-${OCI_BIN:-oci}}"
oci_auth="${oci_auth:-${VN_NEWS_OCI_AUTH:-instance_principal}}"

oci_command() {
  local auth_args=()

  if [[ "$oci_auth" != "default" ]]; then
    auth_args=(--auth "$oci_auth")
  fi
  "$oci_bin" "$@" "${auth_args[@]}"
}
