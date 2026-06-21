#!/usr/bin/env bash

data_device() {
  if [[ -n "${VN_NEWS_DATA_DEVICE:-}" ]]; then
    printf '%s\n' "$VN_NEWS_DATA_DEVICE"
    return
  fi

  if [[ -b /dev/oracleoci/oraclevdb ]]; then
    printf '%s\n' /dev/oracleoci/oraclevdb
    return
  fi

  if [[ -b /dev/sdb ]]; then
    printf '%s\n' /dev/sdb
    return
  fi

  return 1
}

assert_not_root_disk() {
  local device="$1"
  local root_source root_parent device_real device_base

  root_source="$(findmnt -n -o SOURCE /)"
  root_parent="$(lsblk -ndo PKNAME "$root_source" 2>/dev/null || true)"
  device_real="$(readlink -f "$device")"
  device_base="$(basename "$device_real")"

  if [[ -n "$root_parent" && "$device_base" == "$root_parent" ]]; then
    echo "Refusing to use root disk as data volume: $device" >&2
    exit 1
  fi
}

mount_data_volume() {
  local mount_point="/srv/vn-news-data"
  local device uuid
  local redpanda_uid="${VN_NEWS_REDPANDA_DATA_UID:-101}"
  local redpanda_gid="${VN_NEWS_REDPANDA_DATA_GID:-101}"
  local seaweedfs_uid="${VN_NEWS_SEAWEEDFS_UID:-1000}"
  local seaweedfs_gid="${VN_NEWS_SEAWEEDFS_GID:-1000}"
  local polaris_db_uid="${VN_NEWS_POLARIS_DB_UID:-999}"
  local polaris_db_gid="${VN_NEWS_POLARIS_DB_GID:-999}"

  log "Configuring data volume"
  ensure_dir "$mount_point" 0775 root:vn-news

  if findmnt -rn "$mount_point" >/dev/null 2>&1; then
    log "Data volume already mounted at $mount_point"
  else
    if ! device="$(data_device)"; then
      echo "Data volume not found. Set VN_NEWS_DATA_DEVICE=/dev/<device> and rerun." >&2
      exit 1
    fi

    assert_not_root_disk "$device"

    if ! blkid "$device" >/dev/null 2>&1; then
      log "Formatting $device as xfs"
      mkfs.xfs -f "$device"
    fi

    uuid="$(blkid -s UUID -o value "$device")"
    if [[ -z "$uuid" ]]; then
      echo "Could not read filesystem UUID from $device" >&2
      exit 1
    fi

    if ! grep -q "UUID=${uuid}[[:space:]]" /etc/fstab; then
      printf 'UUID=%s %s xfs defaults,nofail,x-systemd.device-timeout=30 0 2\n' "$uuid" "$mount_point" >>/etc/fstab
    fi

    mount "$mount_point"
  fi

  chown root:vn-news "$mount_point"
  chmod 0775 "$mount_point"
  ensure_dir "$mount_point/redpanda" 0775 root:vn-news
  chown -R "$redpanda_uid:$redpanda_gid" "$mount_point/redpanda"
  chmod 0750 "$mount_point/redpanda"
  ensure_dir "$mount_point/seaweedfs" 0775 root:vn-news
  chown -R "$seaweedfs_uid:$seaweedfs_gid" "$mount_point/seaweedfs"
  chmod 0750 "$mount_point/seaweedfs"
  ensure_dir "$mount_point/polaris-postgres" 0775 root:vn-news
  chown -R "$polaris_db_uid:$polaris_db_gid" "$mount_point/polaris-postgres"
  chmod 0750 "$mount_point/polaris-postgres"
}
