COMPOSE := docker compose -f compose.yaml
ALL_PROFILES := \
  --profile core \
  --profile lakehouse \
  --profile processing \
  --profile serving \
  --profile observability \
  --profile orchestration \
  --profile ingestion

# Profiles
.PHONY: up-core down-core logs-core status-core
.PHONY: up-lakehouse down-lakehouse logs-lakehouse status-lakehouse
.PHONY: up-processing down-processing logs-processing status-processing
.PHONY: up-serving down-serving logs-serving status-serving
.PHONY: up-obs down-obs logs-obs status-obs
.PHONY: up-ingestion down-ingestion logs-ingestion status-ingestion

up-core:
	$(COMPOSE) --profile core up -d --wait
down-core:
	$(COMPOSE) --profile core down
logs-core:
	$(COMPOSE) --profile core logs --follow
status-core:
	$(COMPOSE) --profile core ps

up-lakehouse:
	$(COMPOSE) --profile lakehouse up -d --wait
down-lakehouse:
	$(COMPOSE) --profile lakehouse down
logs-lakehouse:
	$(COMPOSE) --profile lakehouse logs --follow
status-lakehouse:
	$(COMPOSE) --profile lakehouse ps

up-processing:
	$(COMPOSE) --profile processing up -d --wait
down-processing:
	$(COMPOSE) --profile processing down
logs-processing:
	$(COMPOSE) --profile processing logs --follow
status-processing:
	$(COMPOSE) --profile processing ps

up-serving:
	$(COMPOSE) --profile serving up -d --wait
down-serving:
	$(COMPOSE) --profile serving down
logs-serving:
	$(COMPOSE) --profile serving logs --follow
status-serving:
	$(COMPOSE) --profile serving ps

up-obs:
	$(COMPOSE) --profile observability up -d --wait
down-obs:
	$(COMPOSE) --profile observability down
logs-obs:
	$(COMPOSE) --profile observability logs --follow
status-obs:
	$(COMPOSE) --profile observability ps

# Ingestion services
up-ingestion:
	$(COMPOSE) --profile core --profile ingestion up -d --wait article-fetcher article-extractor
down-ingestion:
	$(COMPOSE) --profile core --profile ingestion stop article-fetcher article-extractor
logs-ingestion:
	$(COMPOSE) --profile core --profile ingestion logs --follow article-fetcher article-extractor
status-ingestion:
	$(COMPOSE) --profile core --profile ingestion ps article-fetcher article-extractor

# Orchestration
.PHONY: init-orch up-orch down-orch logs-orch status-orch

init-orch:
	$(COMPOSE) --profile orchestration run --rm airflow-scheduler airflow db migrate
up-orch:
	$(COMPOSE) --profile orchestration up -d --wait
down-orch:
	$(COMPOSE) --profile orchestration down
logs-orch:
	$(COMPOSE) --profile orchestration logs --follow
status-orch:
	$(COMPOSE) --profile orchestration ps

# Stack
.PHONY: up down logs status pull

up:
	$(COMPOSE) $(ALL_PROFILES) up -d --wait
down:
	$(COMPOSE) $(ALL_PROFILES) down
logs:
	$(COMPOSE) $(ALL_PROFILES) logs --follow
status:
	$(COMPOSE) $(ALL_PROFILES) ps
pull:
	$(COMPOSE) $(ALL_PROFILES) pull

# Services
.PHONY: service-up service-down service-logs service-pull

service-up:
	test -n "$(SERVICE)" || (echo "Usage: make service-up SERVICE=<name>" && exit 1)
	$(COMPOSE) up -d --no-deps --wait $(SERVICE)
service-down:
	test -n "$(SERVICE)" || (echo "Usage: make service-down SERVICE=<name>" && exit 1)
	$(COMPOSE) stop $(SERVICE)
service-logs:
	test -n "$(SERVICE)" || (echo "Usage: make service-logs SERVICE=<name>" && exit 1)
	$(COMPOSE) logs --follow $(SERVICE)
service-pull:
	test -n "$(SERVICE)" || (echo "Usage: make service-pull SERVICE=<name>" && exit 1)
	$(COMPOSE) pull $(SERVICE)
