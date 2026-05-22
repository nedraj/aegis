# Project Aegis - Implementation Plan (Phases 1-4 Complete)

**Status:** All core phases (1-4) implemented. Phase 4 delivers true zero-NAT capability via custom golden images.

**Date:** 2026-05 (initial build)
**Repo Root:** `/aegis` (this workspace)

## Defined Phases (Inferred from req.md + Practical PoC Constraints)

### Phase 1: CLI Foundation & Profile-Driven Generator (Core "Generator")
**Goal:** Working `aegis-cli` binary that:
- Loads YAML profiles (`gcp-demo`, `airgap-sim`)
- Uses `go:embed` to bundle static manifests, scripts, and templates
- `generate` command renders final K8s YAMLs + bootstrap scripts tailored to profile (e.g., GPU node selector for gcp-demo, bundle-only paths for airgap-sim)
- `version`, `profiles list`, `validate` subcommands
- Deterministic: same profile + same embed = identical output

**Key Deliverables (this phase):**
- `cmd/aegis-cli/main.go` + Cobra CLI
- `internal/profiles/` : profile structs + loader + defaults
- `internal/generator/` : renderer using text/template or yaml merge + embed.FS
- Embedded FS: `manifests/k8s/*.yaml`, `scripts/bootstrap/*.sh` (template-able)
- `profiles/gcp-demo.yaml`, `profiles/airgap-sim.yaml`
- Basic `aegis-cli generate --profile gcp-demo --out ./out/`

**Tech:**
- Go 1.23+
- `github.com/spf13/cobra`
- `gopkg.in/yaml.v3`
- `text/template` for light rendering (image tags, resource limits per profile)

**Exit Criteria:** `go run ./cmd/aegis-cli generate --help` works and produces output files.

---

### Phase 2: Low-Power AI Stack & Containerized Workloads (The "Workflow")
**Goal:** Complete, self-contained AI inference + orchestration layer that runs 100% locally.

**Components:**
1. **Inference Server:** Ollama (container `ollama/ollama:latest`) running `phi3:mini` (3.8B, 4k ctx). 
   - Why Ollama vs vLLM: Simpler air-gap model loading (blob dir copy), excellent T4/CUDA support, OpenAI-compatible `/v1` API.
2. **Mission Control API (Python):** FastAPI service (`mission-control/`)
   - Endpoints: `POST /query` (simple JSON { "prompt": "..." }), `GET /health`, `GET /model-info`
   - **Strictly no external calls**: Only forwards to `http://ollama:11434/api/generate` or `/v1/chat/completions` inside cluster.
   - Returns "Mission Update" style responses (demo flavor text).
   - Containerized with its own Dockerfile.
3. **Local Registry (Zot):** `ghcr.io/project-zot/zot:latest` (minimal OCI registry). Deployed for completeness + future image serving. (Images primarily pre-imported to containerd for speed.)
4. **GPU Support:** NVIDIA Device Plugin for K8s + node labels/taints for GPU workloads.
5. **K8s Manifests (all in `manifests/k8s/`):**
   - `namespace.yaml`
   - `ollama-deployment.yaml` (with GPU limits, model volume)
   - `mission-control-deployment.yaml` + Service
   - `zot-registry.yaml` (optional)
   - `nvidia-device-plugin.yaml` (DaemonSet from NVIDIA)
   - `networkpolicy.yaml` (deny egress except DNS + intra-ns for demo)
   - `kustomization.yaml` or plain yamls for simplicity

**Model Bundling Strategy (Phase 2+3):**
- Connected stage: `docker run -v ./staging/models:/root/.ollama ollama/ollama ollama pull phi3:mini`
- Tar the model dir → included in `.bundle`
- Bootstrap on target mounts it as hostPath /opt/aegis/models → container /root/.ollama ; Ollama auto-detects.

**Python Tech:**
- FastAPI + uvicorn + httpx (for local calls only)
- `mission-control/requirements.txt`
- Dockerfile that produces small image.

**Exit Criteria (Phase 2):** 
- `kubectl apply -f manifests/k8s/` succeeds conceptually
- Mission Control pod + Ollama pod scheduled with `nvidia.com/gpu: 1`
- Local curl to mission-control returns Phi-3 generated text (simulated in unit test if no GPU)

---

### Phase 3: Dependency Bundling, IaC & Air-Gap Bootstrap (The "Foolproof" Pipeline)
**Goal:** One-command (or few) path from connected workstation → fully air-gapped GCP VM running the stack.

**Sub-Parts:**

#### 3.1 Bundle Pipeline (`scripts/bundle/` + CLI integration)
- `bundle.sh` or Python `bundler.py`: 
  - Pulls required OCI images: `ollama/ollama`, `ghcr.io/project-zot/zot`, `nvcr.io/nvidia/k8s-device-plugin` (or official `registry.k8s.io/nvidia-gpu-device-plugin`)
  - `docker save | gzip` → `staging/images/`
  - Downloads K3s airgap assets if possible (`k3s` binary + optional images tar from https://github.com/k3s-io/k3s/releases but for demo we document `curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_DOWNLOAD=true ...` + pre-cache)
  - Runs Ollama pull into `staging/models/`
  - Generates `manifests/bundle-manifest.json` with SHA256 for **every** file
  - `aegis-cli bundle --profile airgap-sim --staging-dir ./staging --out ./aegis-v1.bundle` (tar.gz + checksum sidecar)
- Verification command: `aegis-cli verify-bundle aegis-v1.bundle`

#### 3.2 Infrastructure as Code (`iac/pulumi/`)
- Pulumi Go program (`Pulumi.yaml` + `main.go`)
- Resources created:
  - GCP Project (assumes existing or creates)
  - VPC + Subnet (regional, private)
  - Cloud NAT (for **initial** bootstrap only - documented removal step)
  - Firewall rules (SSH, internal k8s, API access)
  - Compute Instance: `n1-standard-4` + 1x `nvidia-tesla-t4` (guest accelerator)
    - Boot disk: Ubuntu 22.04 LTS minimal
    - Optional: attached Persistent Disk (`aegis-bundle-disk`) for the `.bundle` (large disk)
  - Service Account with minimal perms
- **cloud-init / startup-script** (embedded or generated):
  - Partition + mount extra disk if used
  - `apt-get` for base packages (build-essential, curl, ca-cert, containerd prerequisites) — runs while NAT is present
  - Install NVIDIA drivers + CUDA toolkit (via `ubuntu-drivers autoinstall` + NVIDIA CUDA repo key; **this step requires internet**)
  - Install K3s (airgap-friendly flags: `--docker=false --container-runtime-endpoint ...` or standard + image preload dir `/var/lib/rancher/k3s/agent/images/`)
  - Copy/extract bundle from attached disk or `/opt/aegis`
  - Run `bootstrap.sh` (from bundle):
    - Import all `images/*.tar` via `ctr -n k8s.io image import`
    - Untar models into `/opt/aegis/models`
    - Write `/etc/rancher/k3s/config.yaml` + registries if Zot used
    - `systemctl enable --now k3s`
    - `kubectl apply -f /opt/aegis/manifests/`
    - Wait for pods ready, run smoke test
- **Post-bootstrap air-gap simulation step** (manual or script): `gcloud compute instances remove-access-config` or delete Cloud NAT router + confirm via VPC flow logs or `tcpdump` that no unexpected egress occurs during inference.

**Note on Drivers:** Full zero-internet driver install is hard (NVIDIA .run files are 500MB+). For demo we:
- Document GCP "installable" driver path (initial NAT window)
- Provide alternative: "use a pre-baked custom image with drivers + k3s preinstalled" (future Phase 4)

#### 3.3 CLI Integration for Deploy
- `aegis-cli deploy --profile gcp-demo` (thin wrapper that invokes `pulumi up` with stack config + passes generated manifests + bundle path)
- Or separate: user runs Pulumi directly after `aegis-cli generate`

**Exit Criteria (Phase 3):**
- `aegis-cli bundle ...` produces a verifiable `.bundle` with checksums
- Pulumi program `pulumi preview` succeeds (with valid GCP creds)
- `docs/RUNBOOK.md` contains exact commands to go from `go run ./cmd/aegis-cli generate` → GCP VM SSH → `curl http://mission-control...` answering a "Mission Update" query using only local compute.

---

## Cross-Cutting Decisions & Trade-offs

| Area                  | Choice                          | Rationale / Trade-off |
|-----------------------|---------------------------------|-----------------------|
| Inference             | Ollama (phi3:mini)             | Easiest model air-gap (dir copy), OpenAI compat, mature CUDA on T4 |
| K8s Distro            | K3s (single-node)              | Lightweight, excellent airgap support docs, low RAM/CPU for edge sim |
| Registry              | Zot (deployed) + ctr import    | Meets "Local Image Registry (Zot)" req; ctr import gives fast pod startup |
| IaC                   | Pulumi (Go)                    | Same language as CLI; modern, good GCP support; can embed generator later |
| Bundle Format         | `.tar.gz` + `SHA256SUMS`       | Simple, verifiable with `sha256sum -c`, portable |
| Model Weights         | Ollama blob dir tar            | ~2.5GB for phi3:mini; fits T4 16GB VRAM easily (quantized by Ollama) |
| GPU Driver Strategy   | Initial-NAT + apt/cuda + docs for custom image | Pragmatic for demo; true air-gap image baking is separate concern |
| Mission Control       | FastAPI (Python 3.11 slim)     | Tiny, async, easy to show "no external egress" in code review |
| Validation            | `e2e-validate.sh` + kubectl exec | Runs the 3 success criteria from section 4 of req.md |

## Repository Layout (Final Target)

```
/aegis
├── cmd/aegis-cli/
│   └── main.go                 # Cobra root + subcommands (generate, bundle, verify, deploy)
├── internal/
│   ├── profiles/               # YAML unmarshal + validation
│   ├── generator/              # EmbedFS + template rendering engine
│   └── embed/                  # //go:embed directives (manifests, scripts, profiles)
├── manifests/
│   └── k8s/                    # All raw + template yamls (ollama, mission-control, etc.)
├── mission-control/
│   ├── app.py                  # FastAPI
│   ├── Dockerfile
│   └── requirements.txt
├── scripts/
│   └── bundle/
│       ├── mirror-images.sh
│       ├── prepare-models.sh
│       └── bundler.py
├── iac/
│   └── pulumi/
│       ├── Pulumi.yaml
│       ├── go.mod
│       └── main.go             # GCP resources + cloud-init user-data generator
├── docs/
│   ├── PLAN.md                 # This file
│   ├── RUNBOOK.md              # Exact operator commands for demo
│   └── architecture.md
├── profiles/                   # Source YAML profiles (copied into embed)
├── go.mod
├── README.md
└── requirements.md             # Original (req.md copied here)
```

## Phase Completion Order (This Session)

1. **Scaffolding + Phase 1** (CLI + profiles + generator + embedded hello world manifests)
2. **Phase 2** (Full manifests + Mission Control Python + Ollama deployment yaml)
3. **Phase 3** (Bundle scripts + checksum + basic Pulumi skeleton + bootstrap.sh + RUNBOOK)

After Phase 3 we will have a **minimum viable PoC** that a developer with GCP + T4 quota + NVIDIA account can execute end-to-end (modulo driver install time).

## Phase Completion Status (May 2026)

| Phase | Status     | Key Deliverables |
|-------|------------|------------------|
| 1     | ✅ Done    | CLI, profiles, generator, go:embed |
| 2     | ✅ Done    | Full K8s manifests, Mission Control FastAPI, Ollama |
| 3     | ✅ Done    | Bundle pipeline, Pulumi IaC, bootstrap, RUNBOOK |
| **4** | **✅ Done** | **Golden Image (Packer + 5 provisioners), gcp-hardened profile, zero-NAT Pulumi support, comprehensive ONBOARDING.md with 5 professional diagrams** |

## Future Phases (Out of Scope for v0.1)
- Phase 5: Full vLLM + TensorRT-LLM path + quantization profiles
- Phase 6: Multi-node edge cluster profile + storage (Longhorn)
- Phase 7: SBOM + signed bundles + cosign + SBOM verification in bootstrap
- Phase 8: Web UI for bundle inspection + one-click validation reports  ✅ (implemented as `aegis-cli inspect`)

---

**Implementation Notes for Agent:**
- Prioritize working `go build` and `python -m uvicorn` over perfect production polish.
- Every generated file must be usable immediately (`go run`, `docker build`, `pulumi preview`).
- Include generous comments + example "Mission Update: ..." prompts in Mission Control.
- No external API keys or internet-dependent code paths in the runtime containers.
- All large assets (models, images) are generated on-demand during `bundle` step (never committed to git).

This plan is now the source of truth for the build. Proceed to code.
