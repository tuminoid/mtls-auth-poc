.PHONY: help run clean kind-create kind-delete generate-secrets deploy-cilium
.PHONY: enable-mtls e2e-test validate perf

CLUSTER_NAME ?= mtls-poc

help:
	@echo "Cilium Ztunnel mTLS POC targets:"
	@echo ""
	@echo "  make run           - Full e2e: cluster, deploy, test"
	@echo "  make clean         - Delete Kind cluster"
	@echo "  make validate      - Validate deployment"
	@echo ""

run: kind-delete kind-create generate-secrets deploy-cilium enable-mtls e2e-test validate
	@echo ""
	@echo "=== Cilium Ztunnel mTLS POC Complete ==="

clean: kind-delete

kind-create:
	@./scripts/kind-create.sh

kind-delete:
	@./scripts/kind-delete.sh

generate-secrets:
	@./scripts/generate-secrets.sh

deploy-cilium:
	@./scripts/deploy-cilium.sh

enable-mtls:
	@./scripts/enable-mtls.sh

e2e-test:
	@./scripts/e2e-test.sh

validate:
	@./scripts/validate.sh

perf:
	@../hack/perf-test.sh
