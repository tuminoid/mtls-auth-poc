.PHONY: help lint shellcheck markdownlint test clean all
.PHONY: cilium cilium-clean cilium-ztunnel cilium-ztunnel-clean
.PHONY: istio istio-clean envoy envoy-clean ghostunnel ghostunnel-clean

# Default target
help:
	@echo "mTLS Authentication POC - Available targets:"
	@echo ""
	@echo "POC targets:"
	@echo "  make cilium        - Run Cilium mTLS POC (Kind + WireGuard + SPIRE)"
	@echo "  make cilium-clean  - Clean up Cilium POC"
	@echo "  make cilium-ztunnel - Run Cilium Ztunnel mTLS POC (Kind + ztunnel)"
	@echo "  make cilium-ztunnel-clean - Clean up Cilium Ztunnel POC"
	@echo "  make istio         - Run Istio Ambient mTLS POC (Kind + Cilium + ztunnel)"
	@echo "  make istio-clean   - Clean up Istio POC"
	@echo "  make envoy         - Run Envoy per-node mTLS POC (standalone SPIRE)"
	@echo "  make envoy CNI=calico - Run Envoy POC with Calico instead of Cilium"
	@echo "  make envoy-clean   - Clean up Envoy POC"
	@echo "  make ghostunnel    - Run Ghostunnel sidecar mTLS POC (standalone SPIRE)"
	@echo "  make ghostunnel CNI=calico - Run Ghostunnel POC with Calico"
	@echo "  make ghostunnel-clean - Clean up Ghostunnel POC"
	@echo ""
	@echo "Core targets:"
	@echo "  make lint          - Run all linters"
	@echo "  make test          - Run tests"
	@echo "  make clean         - Clean all POCs"
	@echo "  make all           - Run lint and test"
	@echo ""

# Linting
lint: shellcheck markdownlint

shellcheck:
	@./hack/shellcheck.sh

markdownlint:
	markdownlint-cli2 "**/*.md" "#CONTEXT.md"

# Test
test:
	@echo "No tests configured"

# Clean all
clean: cilium-clean cilium-ztunnel-clean istio-clean envoy-clean ghostunnel-clean

all: lint test

# Cilium POC
cilium:
	@$(MAKE) -C cilium run

cilium-clean:
	@$(MAKE) -C cilium clean

# Cilium Ztunnel POC
cilium-ztunnel:
	@$(MAKE) -C cilium-ztunnel run

cilium-ztunnel-clean:
	@$(MAKE) -C cilium-ztunnel clean

# Istio POC
istio:
	@$(MAKE) -C istio run

istio-clean:
	@$(MAKE) -C istio clean

# Envoy POC
envoy:
	@$(MAKE) -C envoy run CNI=$(CNI)

envoy-clean:
	@$(MAKE) -C envoy clean

# Ghostunnel POC
ghostunnel:
	@$(MAKE) -C ghostunnel run CNI=$(CNI)

ghostunnel-clean:
	@$(MAKE) -C ghostunnel clean
