DATA_COMPOSE := docker compose --env-file .env -f compose.data.yaml
CONTROL_COMPOSE := docker compose --env-file .env -f compose.control.yaml
PROCESSING_COMPOSE := docker compose --env-file .env -f compose.processing.yaml

.PHONY: pull-data up-data down-data logs-data status-data
.PHONY: pull-control init-control up-control down-control logs-control status-control
.PHONY: pull-processing up-processing down-processing logs-processing status-processing
.PHONY: prune-airflow-tasks prune-airflow-tasks-execute

# Data node: Redpanda and SeaweedFS
pull-data:
	$(DATA_COMPOSE) pull
up-data:
	$(DATA_COMPOSE) up -d --wait
down-data:
	$(DATA_COMPOSE) down
logs-data:
	$(DATA_COMPOSE) logs --follow
status-data:
	$(DATA_COMPOSE) ps

# Control node: Airflow runtime
pull-control:
	$(CONTROL_COMPOSE) pull
init-control:
	$(CONTROL_COMPOSE) up -d --wait airflow-db
	$(CONTROL_COMPOSE) --profile bootstrap run --rm airflow-bootstrap
up-control:
	$(CONTROL_COMPOSE) up -d --wait
down-control:
	$(CONTROL_COMPOSE) down
logs-control:
	$(CONTROL_COMPOSE) logs --follow
status-control:
	$(CONTROL_COMPOSE) ps
prune-airflow-tasks:
	scripts/prune_airflow_task_containers.sh --older-than-hours $${VN_NEWS_TASK_CONTAINER_RETENTION_HOURS:-24}
prune-airflow-tasks-execute:
	scripts/prune_airflow_task_containers.sh --older-than-hours $${VN_NEWS_TASK_CONTAINER_RETENTION_HOURS:-24} --execute

# Processing node: long-running consumers
pull-processing:
	$(PROCESSING_COMPOSE) pull
up-processing:
	$(PROCESSING_COMPOSE) up -d --wait
down-processing:
	$(PROCESSING_COMPOSE) down
logs-processing:
	$(PROCESSING_COMPOSE) logs --follow
status-processing:
	$(PROCESSING_COMPOSE) ps
