.PHONY: help run clean kind-create kind-delete deploy-cilium deploy-all
.PHONY: enable-mtls demo e2e-test validate perf

CLUSTER_NAME ?= mtls-poc

help:
	@echo "Cilium mTLS POC targets:"
	@echo ""
	@echo "  make run           - Full e2e: cluster, deploy, test"
	@echo "  make clean         - Delete Kind cluster"
	@echo "  make validate      - Validate deployment"
	@echo ""

run: kind-delete kind-create deploy-all enable-mtls e2e-test validate
	@echo ""
	@echo "=== Cilium mTLS POC Complete ==="

clean: kind-delete

kind-create:
	@./scripts/kind-create.sh

kind-delete:
	@./scripts/kind-delete.sh

deploy-cilium:
	@./scripts/deploy-cilium.sh

deploy-all: deploy-cilium

enable-mtls:
	@./scripts/enable-mtls.sh

demo:
	@./scripts/demo.sh

e2e-test:
	@./scripts/e2e-test.sh

validate:
	@./scripts/validate.sh

perf:
	@../hack/perf-test.sh
