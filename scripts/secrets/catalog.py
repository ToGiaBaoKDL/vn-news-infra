from __future__ import annotations

ROLE_NAMES = ("data", "control", "processing")


SECRET_NAMES = {
    "seaweedfs_s3_config": "tgb-vn-news-seaweedfs-s3-config",
    "storage_admin_s3_credentials": "tgb-vn-news-storage-admin-s3-credentials",
    "ingestion_s3_credentials": "tgb-vn-news-ingestion-s3-credentials",
    "polaris_client_credentials": "tgb-vn-news-polaris-client-credentials",
    "polaris_db_password": "tgb-vn-news-polaris-db-password",
    "polaris_bootstrap_admin": "tgb-vn-news-polaris-bootstrap-admin",
    "spark_rpc_auth_secret": "tgb-vn-news-spark-rpc-auth-secret",
    "airflow_db_password": "tgb-vn-news-airflow-db-password",
    "airflow_api_jwt_secret": "tgb-vn-news-airflow-api-jwt-secret",
    "airflow_fernet_key": "tgb-vn-news-airflow-fernet-key",
    "airflow_admin_password": "tgb-vn-news-airflow-admin-password",
    "cloudflare_data_tunnel_token": "tgb-vn-news-cloudflare-data-tunnel-token",
    "cloudflare_control_tunnel_token": "tgb-vn-news-cloudflare-control-tunnel-token",
}

SECRET_ENV_VARS = {
    "seaweedfs_s3_config": "VN_NEWS_SEAWEEDFS_S3_CONFIG_SECRET_OCID",
    "storage_admin_s3_credentials": "VN_NEWS_STORAGE_ADMIN_S3_CREDENTIALS_SECRET_OCID",
    "ingestion_s3_credentials": "VN_NEWS_INGESTION_S3_CREDENTIALS_SECRET_OCID",
    "polaris_client_credentials": "VN_NEWS_POLARIS_CLIENT_CREDENTIALS_SECRET_OCID",
    "polaris_db_password": "VN_NEWS_POLARIS_DB_PASSWORD_SECRET_OCID",
    "polaris_bootstrap_admin": "VN_NEWS_POLARIS_BOOTSTRAP_ADMIN_SECRET_OCID",
    "spark_rpc_auth_secret": "VN_NEWS_SPARK_RPC_AUTH_SECRET_OCID",
    "airflow_db_password": "VN_NEWS_AIRFLOW_DB_PASSWORD_SECRET_OCID",
    "airflow_api_jwt_secret": "VN_NEWS_AIRFLOW_API_JWT_SECRET_OCID",
    "airflow_fernet_key": "VN_NEWS_AIRFLOW_FERNET_KEY_SECRET_OCID",
    "airflow_admin_password": "VN_NEWS_AIRFLOW_ADMIN_PASSWORD_SECRET_OCID",
    "cloudflare_data_tunnel_token": "VN_NEWS_CLOUDFLARE_DATA_TUNNEL_TOKEN_SECRET_OCID",
    "cloudflare_control_tunnel_token": "VN_NEWS_CLOUDFLARE_CONTROL_TUNNEL_TOKEN_SECRET_OCID",
}

GENERATED_SECRET_KEYS = (
    "seaweedfs_s3_config",
    "storage_admin_s3_credentials",
    "ingestion_s3_credentials",
    "polaris_client_credentials",
    "polaris_db_password",
    "polaris_bootstrap_admin",
    "spark_rpc_auth_secret",
    "airflow_db_password",
    "airflow_api_jwt_secret",
    "airflow_fernet_key",
    "airflow_admin_password",
)

ROLE_SECRET_KEYS = {
    "data": (
        "seaweedfs_s3_config",
        "storage_admin_s3_credentials",
        "polaris_client_credentials",
        "polaris_db_password",
        "polaris_bootstrap_admin",
        "cloudflare_data_tunnel_token",
    ),
    "control": (
        "ingestion_s3_credentials",
        "polaris_client_credentials",
        "spark_rpc_auth_secret",
        "airflow_db_password",
        "airflow_api_jwt_secret",
        "airflow_fernet_key",
        "airflow_admin_password",
        "cloudflare_control_tunnel_token",
    ),
    "processing": (
        "ingestion_s3_credentials",
        "spark_rpc_auth_secret",
    ),
}

LEGACY_STORAGE_ADMIN_IDENTITY_NAME = "vn-news-platform-admin"
STORAGE_ADMIN_IDENTITY_NAME = "vn-news-storage-admin"
