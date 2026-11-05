# Developer shortcuts. Run `make help` for the list.
# Everything runs inside ./.venv (created by `make install`).

VENV    ?= .venv
PYTHON  := $(VENV)/bin/python
PIP     := $(PYTHON) -m pip
HOST    ?= 127.0.0.1
PORT    ?= 8000

.DEFAULT_GOAL := help

.PHONY: help install run test cov lint format typecheck check migrate migration downgrade docker-build clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[1m%-13s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

$(PYTHON):
	python3 -m venv $(VENV)

install: $(PYTHON) ## Create .venv and install runtime + dev dependencies
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements-dev.txt

run: ## Start the API with auto-reload (needs backend/.env)
	$(PYTHON) -m uvicorn app.main:create_app --factory --reload --host $(HOST) --port $(PORT)

test: ## Run the test suite (SQLite; set TEST_DATABASE_URL to use PostgreSQL)
	$(PYTHON) -m pytest

cov: ## Run the tests with a coverage report (fails below 90 %)
	$(PYTHON) -m pytest --cov=app --cov-report=term-missing --cov-fail-under=90

lint: ## Static checks: ruff lint + format check
	$(PYTHON) -m ruff check .
	$(PYTHON) -m ruff format --check .

format: ## Auto-fix lint problems and format the code
	$(PYTHON) -m ruff check . --fix
	$(PYTHON) -m ruff format .

typecheck: ## mypy --strict on app/
	$(PYTHON) -m mypy

check: lint typecheck test ## Everything CI runs

migrate: ## Apply all database migrations (alembic upgrade head)
	$(PYTHON) -m alembic upgrade head

downgrade: ## Roll back the most recent migration
	$(PYTHON) -m alembic downgrade -1

migration: ## Create a migration from model changes: make migration m="add foo"
	@test -n "$(m)" || (echo 'usage: make migration m="what changed"' && exit 1)
	$(PYTHON) -m alembic revision --autogenerate -m "$(m)"

docker-build: ## Build the production image
	docker build -t gully-umpire-api:local .

clean: ## Remove caches and local SQLite files
	rm -rf .pytest_cache .mypy_cache .ruff_cache .coverage htmlcov
	find . -name __pycache__ -type d -not -path "./$(VENV)/*" -prune -exec rm -rf {} +
