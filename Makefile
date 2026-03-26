.PHONY: bootstrap lint test check

bootstrap:
	@./scripts/bootstrap-dev.sh

lint:
	@shellcheck -S warning macback lib/*.sh scripts/*.sh

test:
	@./scripts/test.sh

check: lint test
