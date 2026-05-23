# AGENTS.md — Project Aegis Agent Guidelines

This file contains conventions, commands, and rules for AI agents (Grok Build, Claude, Cursor, etc.) working in the Aegis repository.

**Purpose:** Reduce repeated context and ensure consistent, high-quality contributions across long-lived sessions and multiple phases.

---

## 1. Project Overview

**Aegis** is a profile-driven deployment engine for running low-power AI inference stacks (currently Phi-3-mini) in air-gapped or restricted environments, primarily on single-node K3s + NVIDIA T4.

Core components:
- Go CLI (`aegis-cli`) with `go:embed` generator
- Kubernetes manifests as templates
- Python FastAPI "Mission Control" (the only allowed external interface)
- Pluggable inference backends (Ollama + vLLM as of Phase 5)
- Portable `.bundle` format + golden image support (Phase 4+)
- Strong emphasis on determinism, verifiability, and zero-unintended-egress

See:
- [PLAN.md](docs/PLAN.md) — Phased roadmap and status
- [grok-build-usage.md](grok-build-usage.md) — Effective prompting patterns for this project
- [TESTING.md](TESTING.md) — Test matrix, validation checklist, and QA process
- [README.md](README.md) — High-level overview

---

## 2. Essential Commands

```bash
# Build & Generation
make build                    # Build the aegis-cli binary
make generate                 # Generate for default gcp-demo profile
make test-phase5              # Quick generator smoke test for both Ollama and vLLM

# Local Development
make test-local               # Spin up Mission Control + Ollama via docker compose

# Validation (after deploying to a cluster)
make validate                 # Runs scripts/validate.sh (supports ENGINE=ollama|vllm)

# Bundling (staging workstation)
bash scripts/bundle/mirror-images.sh staging
ENGINE=ollama bash scripts/bundle/prepare-models.sh staging   # or ENGINE=vllm
./aegis-cli bundle --profile gcp-demo --manifests out/gcp-demo --staging staging --out aegis.bundle

# Inspection
./aegis-cli inspect aegis.bundle --port 8787
```

**Profile generation examples:**
```bash
./aegis-cli generate --profile gcp-demo   --out out/gcp-demo
./aegis-cli generate --profile gcp-vllm   --out out/gcp-vllm
./aegis-cli generate --profile gcp-hardened --out out/gcp-hardened
```

---

## 3. Architecture & Extension Rules

### Inference Engine Abstraction (Phase 5+)

- **Always** go through the unified variables in Mission Control:
  - `INFERENCE_ENGINE` (`ollama` | `vllm`)
  - `INFERENCE_URL`
- The generator sets these via `RenderContext`.
- New engines must:
  1. Add a `<engine>-deployment.yaml.tpl`
  2. Update the generator filter + context logic
  3. Update `kustomization.yaml.tpl` and `bootstrap.sh.tpl` with conditionals
  4. Add the engine image to `mirror-images.sh` (or make it conditional)
  5. Update `prepare-models.sh` to support the new engine
  6. Add a corresponding profile (e.g. `gcp-vllm.yaml`)
  7. Extend the test matrix in `TESTING.md`

**Never** hardcode `ollama` or `11434` in new code paths without going through the context variables.

### Profiles

- Profiles live in `profiles/`
- They are embedded via `//go:embed` in `assets.go`
- After adding or modifying a profile, run `make test-phase5` (or equivalent) to verify generation.

### Generator (`internal/generator/generator.go`)

- All templating logic lives here.
- `buildContext()` is the single source of truth for values passed to templates.
- When adding new template variables, add them to `RenderContext` and populate them in `buildContext()`.

### Mission Control (`mission-control/app.py`)

- This is the **only** component allowed to speak to the inference backend.
- It must remain engine-agnostic and use only the OpenAI-compatible `/v1` endpoints.
- Runtime code must **never** make external network calls.

### Air-Gap & Safety Rules (Non-Negotiable)

- Deployed containers must have **zero** code paths that reach the public internet.
- All model weights and container images must come from the bundle or golden image.
- `HF_HUB_OFFLINE=1` (or equivalent) must be set for any HF-based inference path.
- When adding new dependencies, prefer vendoring or pre-bundling over runtime downloads.

---

## 4. Documentation Discipline

**When you add significant functionality, you must update:**

1. `TESTING.md` — Add to the test matrix and/or E2E checklist.
2. `PLAN.md` — Update the relevant phase status and deliverables.
3. `grok-build-usage.md` — Capture any new prompting patterns or workflow lessons.
4. This `AGENTS.md` — Only if a new permanent convention emerges.

**Never** leave a feature "working" without corresponding test/validation coverage in `TESTING.md`.

---

## 5. Working with AI Agents (Grok Build, etc.)

Follow the patterns in [grok-build-usage.md](grok-build-usage.md).

**Recommended workflow for non-trivial changes:**

1. **Reference this file and related docs** at the start of the prompt.
2. **State constraints explicitly** ("Do not touch existing Ollama paths", "Only modify generator + new vllm template").
3. **Define success criteria** upfront.
4. **Use Plan Mode** for anything architecturally ambiguous.
5. **Prefer skills** (`/implement`, `/review`, `/check`) over describing the process.
6. At major milestones, run `/flush` to persist decisions into workspace memory.
7. Keep sessions manageable with periodic `/compact`.

**Prompt template (copy-paste friendly):**

```
Context: See AGENTS.md, PLAN.md Phase X, and TESTING.md.
Goal: ...
Constraints: ...
Success Criteria: ...
Process: Use plan mode first. Maintain a visible todo list. After implementation, run `make test-phase5` and update TESTING.md.
```

---

## 6. Coding Style & Quality

- **Go**: Keep the CLI binary small and stdlib-heavy where possible. The generator must remain deterministic.
- **Python (Mission Control)**: Minimal dependencies. FastAPI + httpx + pydantic only. Keep it tiny.
- **Templates**: Use `{{ .Field }}` from `RenderContext`. Prefer conditionals over duplicating files.
- **Validation**: The `scripts/validate.sh` script is the canonical in-cluster smoke test. Keep it engine-aware.
- **No new runtime external calls** in any component that runs inside the air-gapped node.

---

## 7. Common Tasks & How To Approach Them

| Task                              | Recommended Approach |
|-----------------------------------|----------------------|
| Add a new inference engine        | Follow the Phase 5 pattern in `grok-build-usage.md`. Update generator, add `*-deployment.yaml.tpl`, extend prepare-models + mirror-images, new profile, TESTING.md. |
| Add a new profile                 | Copy an existing one, adjust values, run generator test. |
| Change Mission Control behavior   | Must remain compatible with both engines. Add to health/model-info/query as needed. |
| Improve validation                | Extend `scripts/validate.sh` + the matrix in `TESTING.md`. |
| Refactor the generator            | Strong preference for backward compatibility with all existing profiles. |
| Work on golden image / Phase 4+   | See `scripts/image-bake/` and `profiles/gcp-hardened.yaml`. |

---

## 8. File Organization Notes

- `manifests/k8s/*.tpl` — Source of truth for generated manifests
- `internal/generator/` — Single place for rendering logic
- `profiles/` — Source profiles (embedded at build time)
- `scripts/bundle/` — Staging workstation tools
- `scripts/validate.sh` — In-cluster validation (copied into bundles)
- `mission-control/` — The air-gapped API layer

---

**This file is the source of truth for agent behavior in this repository.**

Update it when new permanent conventions emerge. Keep it concise but actionable.

*Maintained as part of Project Aegis development process.*