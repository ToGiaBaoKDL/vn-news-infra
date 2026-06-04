# syntax=docker/dockerfile:1.7
FROM apache/airflow:3.2.2-python3.12

COPY --from=ghcr.io/astral-sh/uv:0.11.17 /uv /usr/local/bin/uv

COPY pyproject.toml uv.lock /opt/airflow/runtime/

USER root

RUN cd /opt/airflow/runtime \
    && uv export --frozen --no-dev --no-emit-project --output-file /tmp/airflow-runtime.txt >/dev/null \
    && uv pip install --system --requirement /tmp/airflow-runtime.txt \
    && rm /tmp/airflow-runtime.txt \
    && install -d -m 0755 -o airflow -g root /opt/airflow/empty-dags

USER airflow
