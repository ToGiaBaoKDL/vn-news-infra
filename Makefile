PLATFORM_COMPOSE := docker compose --env-file .env -f compose.yaml
WORKERS_COMPOSE := docker compose --env-file .env -f compose.workers.yaml

.PHONY: pull-platform init-orch up-platform down-platform logs-platform status-platform
.PHONY: pull-workers up-workers down-workers logs-workers status-workers

# Node 1: Redpanda, SeaweedFS, Docker socket proxy, Airflow
pull-platform:
	$(PLATFORM_COMPOSE) pull
init-orch:
	$(PLATFORM_COMPOSE) up -d --wait airflow-db
	$(PLATFORM_COMPOSE) run --rm airflow-scheduler airflow db migrate
up-platform:
	$(PLATFORM_COMPOSE) up -d --wait
down-platform:
	$(PLATFORM_COMPOSE) down
logs-platform:
	$(PLATFORM_COMPOSE) logs --follow
status-platform:
	$(PLATFORM_COMPOSE) ps

# Node 2: long-running ingestion consumers
pull-workers:
	$(WORKERS_COMPOSE) pull
up-workers:
	$(WORKERS_COMPOSE) up -d --wait
down-workers:
	$(WORKERS_COMPOSE) down
logs-workers:
	$(WORKERS_COMPOSE) logs --follow
status-workers:
	$(WORKERS_COMPOSE) ps
