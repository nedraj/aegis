# Project Aegis

**Air-Gapped AI Platform Deployment Engine (GCP Demo)**

Deterministic, profile-driven deployment of a low-power, fully containerized AI inference stack (Phi-3 + Ollama + K3s) into restricted / zero-internet environments.

> "The last mile of AI infrastructure — field-deployed Special Programs edge nodes."

## Quick Start (Developer Workstation with Internet)

```bash
# 1. Build the generator
go build -o aegis-cli ./cmd/aegis-cli

# 2. See available profiles
./aegis-cli profiles list

# 3. Generate manifests for GCP demo (connected phase)
./aegis-cli generate --profile gcp-demo --out ./out/gcp-demo

# 4. (Later) Create portable air-gap bundle
./aegis-cli bundle --profile airgap-sim --out ./aegis-v1.bundle
```

## Architecture (3 Phases)

See [docs/PLAN.md](./docs/PLAN.md) for the complete phased implementation plan and technical decisions.

**Core Flow:**
1. **Generator (CLI)** — YAML profiles + `go:embed` → rendered K8s manifests + bootstrap scripts
2. **Workflow (AI Stack)** — Ollama (Phi-3 mini) + FastAPI Mission Control + Zot registry + NVIDIA GPU plugin on K3s
3. **Bundle + IaC** — OCI image tarballs + model weights + checksums → Pulumi (Go) provisions T4 VM + cloud-init hydrates everything locally

## Success Criteria (from requirements)

After deployment inside the air-gapped VPC, a single `curl` from within a pod must prove:

1. `nvidia-smi` visible inside GPU pod
2. Phi-3 model loaded from **local persistent volume only**
3. Inference returns a coherent "Mission Update" answer with **zero egress** to the public internet

## Repository Layout

See the tree in [docs/PLAN.md](./docs/PLAN.md#repository-layout-final-target).

## Requirements

- Go 1.23+
- Python 3.11+ (for Mission Control image build)
- Docker / nerdctl / ctr (for image export during bundle)
- Pulumi + `gcloud` auth (for Phase 3 IaC)
- GCP project with T4 GPU quota (n1-standard-4 + 1x Tesla T4)

## License

Internal / Demo — not for production use without security review.

## Status

**Phases 1–4 Complete** (including true zero-NAT golden images).

See:
- [docs/ONBOARDING.md](docs/ONBOARDING.md) — Comprehensive visual guide (recommended starting point)
- [docs/PLAN.md](docs/PLAN.md) — Technical decisions and phase history
- [docs/RUNBOOK.md](docs/RUNBOOK.md) — Exact commands for the full GCP demo
