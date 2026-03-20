.PHONY: run clean cluster deploy e2e-test validate perf perf-transparent

CLUSTER_NAME := mtls-poc
CNI ?= cilium

run: cluster deploy e2e-test validate

cluster:
	./scripts/kind-create.sh

deploy: deploy-cni deploy-spire deploy-ghostunnel

deploy-cni:
	CNI=$(CNI) ./scripts/deploy-cni.sh

deploy-spire:
	./scripts/deploy-spire.sh

deploy-ghostunnel:
	./scripts/deploy-ghostunnel.sh

e2e-test:
	./scripts/e2e-test.sh

validate:
	./scripts/validate.sh

perf:
	./scripts/perf-test.sh

perf-transparent:
	./scripts/perf-transparent.sh

clean:
	./scripts/kind-delete.sh
