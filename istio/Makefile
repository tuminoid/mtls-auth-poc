.PHONY: help run clean kind-create kind-delete deploy-cilium deploy-istio
.PHONY: e2e-test validate perf

CLUSTER_NAME ?= mtls-poc

help:
	@echo "Istio Ambient mTLS POC targets:"
	@echo ""
	@echo "  make run           - Full e2e: cluster, deploy, test"
	@echo "  make clean         - Delete Kind cluster"
	@echo "  make validate      - Validate deployment"
	@echo ""

run: kind-delete kind-create deploy-cilium deploy-istio e2e-test validate
	@echo ""
	@echo "=== Istio Ambient mTLS POC Complete ==="

clean: kind-delete

kind-create:
	@./scripts/kind-create.sh

kind-delete:
	@./scripts/kind-delete.sh

deploy-cilium:
	@./scripts/deploy-cilium.sh

deploy-istio:
	@./scripts/deploy-istio.sh

e2e-test:
	@./scripts/e2e-test.sh

validate:
	@./scripts/validate.sh

perf:
	@../hack/perf-test.sh
