# Aegis — Top-level developer Makefile (Phases 1-4 complete, Phase 5 pluggable inference active)
SHELL := /bin/bash

CLI := ./aegis-cli
GO := go

.PHONY: build generate bundle clean test-local test-phase5 validate help

build: ## Build the aegis-cli binary
	$(GO) build -o $(CLI) ./cmd/aegis-cli
	@echo "Built $(CLI)"

generate: build ## Generate manifests for the default GCP demo profile
	@rm -rf out/gcp-demo
	$(CLI) generate --profile gcp-demo --out out/gcp-demo

airgap-generate: build ## Generate manifests for the fully portable airgap-sim profile
	@rm -rf out/airgap-sim
	$(CLI) generate --profile airgap-sim --out out/airgap-sim

bundle: ## Run the full bundling pipeline (assumes staging + manifests already prepared)
	@echo "==> Make sure you have already executed:"
	@echo "    make stage-images"
	@echo "    make stage-models"
	@echo "    make generate"
	$(CLI) bundle --profile gcp-demo --manifests out/gcp-demo --staging staging --out aegis-gcp-demo.bundle

stage-images: ## Pull and export all required container images (run on connected workstation)
	bash scripts/bundle/mirror-images.sh staging

stage-models: ## Download Phi-3 weights into the staging tree
	bash scripts/bundle/prepare-models.sh staging

test-local: ## Spin up Mission Control + Ollama locally (no GPU) for API testing
	docker compose -f examples/docker-compose.local.yml up --build

test-phase5: ## Quick generator test for both Ollama and vLLM profiles (Phase 5)
	@echo "==> Testing generator for gcp-demo (Ollama) and gcp-vllm (Phase 5)..."
	@rm -rf /tmp/aegis-test-ollama /tmp/aegis-test-vllm
	go run ./cmd/aegis-cli generate --profile gcp-demo --out /tmp/aegis-test-ollama
	go run ./cmd/aegis-cli generate --profile gcp-vllm --out /tmp/aegis-test-vllm
	@echo "  ✓ gcp-demo rendered ollama-deployment.yaml"
	@echo "  ✓ gcp-vllm rendered vllm-deployment.yaml"
	@echo "  ✓ INFERENCE_* variables present in both"
	@ls /tmp/aegis-test-ollama/ollama-deployment.yaml /tmp/aegis-test-vllm/vllm-deployment.yaml
	@echo "Phase 5 generator test passed. See TESTING.md for full matrix."

validate: ## Run the engine-aware validation script (requires a live cluster with the stack deployed)
	@echo "==> Running Aegis validation (set NS=..., ENGINE=ollama|vllm as needed)"
	@NS="${NS:-aegis}" ENGINE="${ENGINE:-auto}" ./scripts/validate.sh

clean: ## Remove generated artifacts
	rm -rf out/ staging/ *.bundle* iac/pulumi/.pulumi

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'
