.PHONY: help run clean kind-create kind-delete deploy-cni deploy-spire deploy-envoy
.PHONY: deploy-iptables deploy-all e2e-test validate perf

CLUSTER_NAME ?= mtls-poc
CNI ?= cilium

help:
	@echo "Envoy Per-Node mTLS POC targets:"
	@echo ""
	@echo "  make run           - Full e2e: cluster, deploy, test (CNI=$(CNI))"
	@echo "  make run CNI=calico - Full e2e with Calico instead of Cilium"
	@echo "  make clean         - Delete Kind cluster"
	@echo "  make validate      - Validate deployment"
	@echo ""

run: kind-delete kind-create deploy-all e2e-test validate
	@echo ""
	@echo "=== Envoy Per-Node mTLS POC Complete (CNI=$(CNI)) ==="

clean: kind-delete

kind-create:
	@./scripts/kind-create.sh

kind-delete:
	@./scripts/kind-delete.sh

deploy-cni:
	@CNI=$(CNI) ./scripts/deploy-cni.sh

deploy-spire:
	@./scripts/deploy-spire.sh

deploy-envoy:
	@./scripts/deploy-envoy.sh

deploy-iptables:
	@./scripts/deploy-iptables.sh

deploy-all: deploy-cni deploy-spire deploy-envoy deploy-iptables

e2e-test:
	@./scripts/e2e-test.sh

validate:
	@./scripts/validate.sh

perf:
	@./scripts/perf-test.sh
