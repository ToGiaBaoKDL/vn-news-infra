from __future__ import annotations


SECRET_NAMES = {
    "seaweedfs_s3_config": "tgb-vn-news-seaweedfs-s3-config",
    "storage_admin_s3_credentials": "tgb-vn-news-storage-admin-s3-credentials",
    "ingestion_s3_credentials": "tgb-vn-news-ingestion-s3-credentials",
    "curated_writer_s3_credentials": "tgb-vn-news-curated-writer-s3-credentials",
    "airflow_db_password": "tgb-vn-news-airflow-db-password",
    "airflow_api_jwt_secret": "tgb-vn-news-airflow-api-jwt-secret",
    "airflow_fernet_key": "tgb-vn-news-airflow-fernet-key",
    "airflow_admin_password": "tgb-vn-news-airflow-admin-password",
    "cloudflare_data_tunnel_token": "tgb-vn-news-cloudflare-data-tunnel-token",
    "cloudflare_control_tunnel_token": "tgb-vn-news-cloudflare-control-tunnel-token",
}

GENERATED_SECRET_KEYS = (
    "seaweedfs_s3_config",
    "storage_admin_s3_credentials",
    "ingestion_s3_credentials",
    "curated_writer_s3_credentials",
    "airflow_db_password",
    "airflow_api_jwt_secret",
    "airflow_fernet_key",
    "airflow_admin_password",
)

ROLE_SECRET_KEYS = {
    "data": (
        "seaweedfs_s3_config",
        "storage_admin_s3_credentials",
        "cloudflare_data_tunnel_token",
    ),
    "control": (
        "ingestion_s3_credentials",
        "airflow_db_password",
        "airflow_api_jwt_secret",
        "airflow_fernet_key",
        "airflow_admin_password",
        "cloudflare_control_tunnel_token",
    ),
    "processing": (
        "ingestion_s3_credentials",
        "curated_writer_s3_credentials",
    ),
}

LEGACY_STORAGE_ADMIN_IDENTITY_NAME = "vn-news-platform-admin"
STORAGE_ADMIN_IDENTITY_NAME = "vn-news-storage-admin"
CURATED_WRITER_IDENTITY_NAME = "vn-news-curated-writer"
