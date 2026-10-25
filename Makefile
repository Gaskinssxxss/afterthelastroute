SHELL := /bin/bash
.PHONY: preflight deploy status validate acceptance incident recover reset evidence destroy lint
preflight:
	./scripts/lab preflight
deploy:
	./scripts/lab deploy
status:
	./scripts/lab status
validate:
	./scripts/lab validate
acceptance:
	./tests/acceptance.sh
incident:
	./scripts/lab incident "$(NAME)"
recover:
	./scripts/lab recover "$(NAME)"
reset:
	./scripts/lab reset
evidence:
	./scripts/lab evidence
destroy:
	./scripts/lab destroy
lint:
	./scripts/lint
