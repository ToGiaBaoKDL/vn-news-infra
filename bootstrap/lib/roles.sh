#!/usr/bin/env bash

configure_data_role() {
  mount_data_volume
}

configure_control_role() {
  local airflow_uid="${VN_NEWS_AIRFLOW_UID:-50000}"
  local airflow_gid="${VN_NEWS_AIRFLOW_GID:-0}"

  ensure_dir /srv/vn-news-control 0775 root:vn-news
  ensure_dir /srv/vn-news-control/airflow-db 0775 root:vn-news
  ensure_dir /srv/vn-news-control/airflow-dag-bundles 0775 root:vn-news
  ensure_dir /srv/vn-news-control/airflow-logs 0775 root:vn-news
  chown -R "$airflow_uid:$airflow_gid" /srv/vn-news-control/airflow-dag-bundles
  chown -R "$airflow_uid:$airflow_gid" /srv/vn-news-control/airflow-logs
  chmod 0770 /srv/vn-news-control/airflow-dag-bundles
  chmod 0770 /srv/vn-news-control/airflow-logs
  ensure_dir /srv/vn-news-control/prometheus 0775 root:vn-news
}

configure_processing_role() {
  ensure_dir /srv/vn-news-processing 0775 root:vn-news
}
