DATA_ENV ?= /etc/vn-news/env/data.env
CONTROL_ENV ?= /etc/vn-news/env/control.env
PROCESSING_ENV ?= /etc/vn-news/env/processing.env
TFVARS ?= terraform/oci/terraform.tfvars.json
ROLE_ENV_OUTPUT_DIR ?= build/env
CLOUDFLARE_BACKEND_CONFIG ?= backend.hcl
PROVISION_SECRETS_ARGS ?=
SYNC_CLOUDFLARE_ARGS ?=

DATA_COMPOSE := docker compose --env-file $(DATA_ENV) -f compose.data.yaml
CONTROL_COMPOSE := docker compose --env-file $(CONTROL_ENV) -f compose.control.yaml
PROCESSING_COMPOSE := docker compose --env-file $(PROCESSING_ENV) -f compose.processing.yaml

.PHONY: pull-data up-data down-data logs-data status-data up-data-access
.PHONY: pull-control init-control up-control down-control logs-control status-control up-control-access
.PHONY: pull-processing up-processing down-processing logs-processing status-processing
.PHONY: prune-airflow-tasks prune-airflow-tasks-execute
.PHONY: resource-manager-create resource-manager-update resource-manager-plan resource-manager-apply
.PHONY: ensure-env-files render-role-envs
.PHONY: cloudflare-init
.PHONY: provision-runtime-secrets sync-cloudflare-secrets

# Data node: Redpanda, SeaweedFS, Polaris, and access tunnel
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
up-data-access:
	$(DATA_COMPOSE) pull cloudflared-data
	$(DATA_COMPOSE) up -d --wait cloudflared-data

# Control node: Airflow, Spark master, and access tunnel
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
up-control-access:
	$(CONTROL_COMPOSE) pull cloudflared-control
	$(CONTROL_COMPOSE) up -d --wait cloudflared-control
prune-airflow-tasks:
	scripts/airflow/prune_task_containers.sh --older-than-hours $${VN_NEWS_TASK_CONTAINER_RETENTION_HOURS:-24}
prune-airflow-tasks-execute:
	scripts/airflow/prune_task_containers.sh --older-than-hours $${VN_NEWS_TASK_CONTAINER_RETENTION_HOURS:-24} --execute

resource-manager-create:
	scripts/resource_manager/stack.sh create
resource-manager-update:
	scripts/resource_manager/stack.sh update

resource-manager-plan:
	scripts/resource_manager/job.sh plan

resource-manager-apply:
	scripts/resource_manager/job.sh apply $(PLAN_JOB_ID)

ensure-env-files:
	scripts/env/ensure_local_files.sh

render-role-envs:
	python3 -m scripts.host.render_role_envs --tfvars $(TFVARS) --output-dir $(ROLE_ENV_OUTPUT_DIR)

cloudflare-init:
	terraform -chdir=terraform/cloudflare init -migrate-state -backend-config=$(CLOUDFLARE_BACKEND_CONFIG)

provision-runtime-secrets:
	uv run python -m scripts.secrets.provision --tfvars $(TFVARS) $(PROVISION_SECRETS_ARGS)

sync-cloudflare-secrets:
	uv run python -m scripts.secrets.sync_cloudflare --oci-tfvars $(TFVARS) $(SYNC_CLOUDFLARE_ARGS)

# Processing node: ingestion consumers, metrics, and Spark worker
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
