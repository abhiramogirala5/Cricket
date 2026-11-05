# Developer shortcuts for the Flutter app. Run `make help` for the list.

.DEFAULT_GOAL := help

.PHONY: help bootstrap get analyze test check run format

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[1m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Create .env, android/ and ios/ and apply the platform settings
	python3 tool/bootstrap_platforms.py

get: ## Install Dart packages
	flutter pub get

analyze: ## Static analysis (must be clean)
	flutter analyze

test: ## Unit and widget tests
	flutter test

check: analyze test ## Everything CI runs

run: ## Run on the connected device or emulator
	flutter run

format: ## Format the Dart code
	dart format lib test
