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
  ensure_dir /srv/vn-news-control/spark 0770 "$airflow_uid:$airflow_gid"
  ensure_dir /srv/vn-news-control/spark/checkpoints 0770 "$airflow_uid:$airflow_gid"
  chown -R "$airflow_uid:$airflow_gid" /srv/vn-news-control/airflow-dag-bundles
  chown -R "$airflow_uid:$airflow_gid" /srv/vn-news-control/airflow-logs
  chmod 0770 /srv/vn-news-control/airflow-dag-bundles
  chmod 0770 /srv/vn-news-control/airflow-logs
  ensure_dir /srv/vn-news-control/prometheus 0775 root:vn-news
}

configure_processing_role() {
  local spark_uid="${VN_NEWS_SPARK_UID:-185}"
  local spark_gid="${VN_NEWS_SPARK_GID:-0}"

  ensure_dir /srv/vn-news-processing 0775 root:vn-news
  ensure_dir /srv/vn-news-processing/spark 0770 "$spark_uid:$spark_gid"
  ensure_dir /srv/vn-news-processing/spark/local 0770 "$spark_uid:$spark_gid"
  ensure_dir /srv/vn-news-processing/spark/work 0770 "$spark_uid:$spark_gid"
}
