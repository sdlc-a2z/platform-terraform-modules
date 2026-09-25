.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help check fmt tag

help:  ## Show this help
	@grep -hE '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | sed 's/:.*##/ —/'

fmt:  ## Format
	terraform fmt -recursive modules/

# No credentials and no project: modules take inputs and read nothing, so they validate
# offline. A module that needed a live project to validate would be breaking that rule.
check: fmt  ## Format and validate every module
	@for d in modules/*/; do \
	  echo "→ $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null || exit 1; \
	  terraform -chdir=$$d validate || exit 1; \
	done
	@terraform fmt -check -recursive modules/ && echo "✓ formatting clean"

tag:  ## Tag a release — consumers pin, so an untagged change reaches nobody
	@test -n "$(VERSION)" || { echo "VERSION=v0.1.1 make tag"; exit 1; }
	$(MAKE) check
	git tag -a $(VERSION) -m "$(VERSION)"
	git push origin $(VERSION)
	@echo "Bump the ref in platform-infra to $(VERSION)."
