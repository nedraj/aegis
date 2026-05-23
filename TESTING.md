# Aegis Testing, QA & Evaluation Plan

**Status:** Phase 5 (pluggable inference) implementation complete for generator + runtime. This document defines the full test strategy.

**Related:**
- [grok-build-usage.md](grok-build-usage.md) — Effective prompting & workflow patterns for Grok Build on this project
- [docs/PLAN.md](docs/PLAN.md) — Phase definitions and status
- [docs/RUNBOOK.md](docs/RUNBOOK.md) — Operator commands for full GCP demo
- [docs/ONBOARDING.md](docs/ONBOARDING.md) — Visual guides + troubleshooting
- [requirements.md](requirements.md) §4 — The three canonical success criteria

---

## 1. Test Philosophy & Levels

Aegis is a **deployment + air-gap engineering tool**, not a pure ML research project. Testing therefore emphasizes:

1. **Determinism & Reproducibility** — Same profile + same inputs → identical (or functionally equivalent) output.
2. **Air-Gap Integrity** — Zero unintentional egress after NAT removal.
3. **Engine Pluggability** (Phase 5+) — Ollama and vLLM must be interchangeable from the operator and Mission Control perspective.
4. **Bundle Portability** — The `.bundle` + golden image must survive sneaker-net transfer and work on first boot with no internet.

### Test Pyramid

| Level              | Scope                              | Automation | Owner          | Frequency          |
|--------------------|------------------------------------|------------|----------------|--------------------|
| Unit / Component   | Go generator, profiles, CLI commands, Python FastAPI logic | High       | Developer      | Every commit / PR  |
| Local Integration  | `docker compose` + Mission Control + real inference (Ollama easy, vLLM CPU possible) | Medium     | Developer      | Daily / on change  |
| Bundle + Inspector | `aegis-cli bundle`, SHA256SUMS, `inspect` web UI | High       | Developer + CI | On bundle changes  |
| E2E (Connected)    | Full `generate → bundle → bootstrap → query` on GCP (with NAT) | Low (manual) | Operator / QA | Per release / major profile change |
| E2E Air-Gap Proof  | Same as above + NAT removal + zero-egress confirmation + VPC Flow Logs | Low (manual) | Operator / Security | Per customer delivery |
| Golden Image       | Packer build + provisioners + hardened profile boot | Low        | Infra          | When image-bake changes |
| Model Quality      | Coherence of "MISSION UPDATE" answers, latency, token usage, GPU memory | Manual + light scripts | ML + Ops       | When changing model/quant/engine |

---

## 2. Quick Start — How to Test Right Now (Developer)

### 2.1 CLI + Generator Smoke (no GPU, no Docker)

```bash
# List profiles (now includes gcp-vllm from Phase 5)
go run ./cmd/aegis-cli profiles list

# Generate for classic (Ollama)
go run ./cmd/aegis-cli generate --profile gcp-demo --out /tmp/out-ollama

# Generate for Phase 5 (vLLM)
go run ./cmd/aegis-cli generate --profile gcp-vllm --out /tmp/out-vllm

# Verify the right deployment was rendered
ls /tmp/out-ollama/*ollama* /tmp/out-vllm/*vllm*
grep -E 'inference|engine' /tmp/out-vllm/profile-used.yaml
```

**Expected:** Only the matching inference deployment file appears. kustomization + bootstrap contain the correct `if` branches (rendered statically).

### 2.2 Local Mission Control + Inference (no GPU required for Ollama)

```bash
# From repo root
make test-local
# or
docker compose -f examples/docker-compose.local.yml up --build
```

In another shell:

```bash
# Health (now engine-aware)
curl http://localhost:8080/health | jq

# Model info
curl http://localhost:8080/model-info | jq

# Real inference
curl -X POST http://localhost:8080/query \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Give a one-sentence status report on the forward sensor array.","max_tokens":80}' | jq
```

**Phase 5 note:** You can point the same Mission Control container at a running vLLM instance (see comments in `examples/docker-compose.local.yml`).

### 2.3 Validate Script (inside cluster or simulated)

The updated [scripts/validate.sh](scripts/validate.sh) now supports both engines:

```bash
# After `kubectl apply` in a real or kind cluster
ENGINE=ollama NS=aegis ./scripts/validate.sh
# or
ENGINE=vllm  NS=aegis INFERENCE_DEPLOY=vllm ./scripts/validate.sh
```

It performs the three canonical checks + engine detection.

### 2.4 Bundle + Inspector

```bash
# After running mirror-images + prepare-models (for either engine)
./aegis-cli bundle --profile gcp-vllm --manifests out/gcp-vllm --staging staging --out aegis-vllm-test.bundle

# Inspect the beautiful web UI
./aegis-cli inspect aegis-vllm-test.bundle --port 8787
```

Open http://localhost:8787 — verify SHA256SUMS, manifest contents, search, etc.

---

## 3. Phase 5 Specific Test Matrix

| Test Case                                      | Ollama (gcp-demo) | vLLM (gcp-vllm) | How to Execute                          | Pass Criteria |
|------------------------------------------------|-------------------|-----------------|-----------------------------------------|---------------|
| Generator produces correct manifests           | ✓                 | ✓               | `generate --profile` + diff inspection  | Only correct deployment + correct `INFERENCE_*` envs + port + service name |
| Mission Control talks OpenAI /v1 to backend    | ✓                 | ✓               | Local docker or real cluster            | `/health`, `/query` succeed; `backend` field in response matches engine |
| NetworkPolicy allows traffic only to inference | ✓                 | ✓               | After `kubectl apply`                   | `aegis/component: inference` label + correct port |
| Model volume mount + offline loading           | ✓                 | ✓               | `validate.sh` step 2                    | Files visible under expected path; no 404s / download attempts in logs |
| GPU resource scheduled & visible               | ✓                 | ✓               | `nvidia-smi` inside the inference pod   | Tesla T4 visible |
| Response contains "MISSION UPDATE:" prefix     | ✓                 | ✓               | `/query` call                           | grep succeeds |
| Air-gap after NAT removal                      | ✓                 | ✓               | Full RUNBOOK + delete NAT + repeat query | Still answers; VPC Flow Logs show no external LLM calls |
| Bundle contains the right inference image      | ✓                 | ✓               | `tar -tzf *.bundle \| grep vllm`        | Correct image tar present |
| Quantization / served-model-name honored       | (via model tag)   | ✓               | vLLM profile + logs                     | Model loads with expected quant / name |
| Inspector shows correct profile & engine       | ✓                 | ✓               | `aegis-cli inspect`                     | `profile-used.yaml` + bundle.json reflect engine |

---

## 4. Full End-to-End Air-Gap QA Checklist (GCP)

Use this when delivering to a customer or doing a security review. Based on [requirements.md §4](requirements.md) + Phase 4/5 enhancements.

### Pre-flight
- [ ] `aegis-cli generate --profile <chosen>` succeeds for both `gcp-demo` and `gcp-vllm`
- [ ] `make stage-images && ENGINE=vllm make stage-models` (or equivalent) completes
- [ ] Bundle created and `sha256sum -c` passes
- [ ] `aegis-cli inspect` opens and all SHA256SUMS verify in the UI

### On the target (after bootstrap)
- [ ] `kubectl get pods -n aegis` — all pods Running (inference, mission-control, nvidia-device-plugin)
- [ ] GPU visible: `kubectl exec deploy/<inference> -- nvidia-smi`
- [ ] Model files present on hostPath (Ollama blobs or HF snapshot under `/models`)
- [ ] Mission Control health returns `"airgap_enforced": true` + correct engine
- [ ] `/query` returns coherent text prefixed with `MISSION UPDATE:`
- [ ] **Air-gap proof:**
  1. Remove Cloud NAT / external IP from the instance
  2. Wait 30–60 s
  3. Repeat the exact `/query` call from inside the cluster
  4. Confirm answer still arrives
  5. (Strong) `gcloud compute instances describe` shows no external IP; VPC Flow Logs for the subnet show zero flows to `*.openai.com`, `*.huggingface.co`, etc. (GCP metadata is the only allowed exception)

### Bonus / Hardening
- [ ] Golden image path: instance booted from `aegis-golden-*` family with zero NAT from the very first packet
- [ ] No secrets or API keys in any generated manifest or bundle
- [ ] `kubectl describe pod <inference>` shows correct resource limits and node selector

---

## 5. Model Response Quality & Light Evaluation

Because Aegis targets **tactical / field use** (not general chat), we care about:

- Consistent "MISSION UPDATE:" framing
- Technical, concise, structured output
- Low hallucination on domain-specific prompts (sensor status, comms, reactor, logistics, etc.)
- Reasonable latency on T4 (target < 8–12 s for 80–120 tokens with Phi-3-mini)

### Manual Eval Prompts (keep a small set in `tests/prompts/` later)

```json
{"prompt": "One-sentence status of the forward sensor array and any anomalies in the last 6 hours."}
{"prompt": "Report reactor coolant pump pressure trends and recommend any immediate actions."}
{"prompt": "Summarize power budget remaining and projected endurance at current load."}
```

**Scoring (simple 1–5 rubric):**
- 5 = Perfect structure + correct technical tone
- 3 = Usable but slightly verbose or minor hallucination
- 1 = Refuses, loops, or fabricates dangerous nonsense

Run 5–10 prompts per engine/quant combination and record in a small `eval-log.md`.

Future: add a tiny Python eval harness that calls the local Mission Control and scores with a stronger judge model (when you have one in the air-gap).

---

## 6. Automation & CI Vision (Future)

Proposed `.github/workflows/` (or equivalent):

- `generate-matrix.yml` — matrix over all profiles, assert `aegis-cli generate` produces expected files + no diff on re-run (idempotency)
- `python-test.yml` — `pytest` on Mission Control (add `tests/` with FastAPI TestClient + mocked backends)
- `bundle-verify.yml` — build a tiny bundle in CI (using cached small images) and run `inspect` + SHA check
- `validate-on-kind` (stretch) — spin up kind + GPU simulator (or CPU-only) and run the validate script

**Current gaps (documented for transparency):**
- Zero Go unit tests (`internal/generator`, `profiles`, CLI)
- No Python tests for `mission-control/app.py`
- `validate.sh` is still somewhat imperative and pod-name based (improved in Phase 5 but can use labels more)
- No automated air-gap proof (by definition requires human + cloud console action)

---

## 7. How to Add / Run Tests Going Forward

1. **Adding a new profile** — always run `generate` for it and commit the diff if intentional.
2. **Changing Mission Control** — run `make test-local`, hit the three endpoints, plus at least one real `/query`.
3. **Changing a template** — re-generate both an Ollama and a vLLM profile; inspect the rendered YAML and bootstrap.sh.
4. **Touching bundle scripts** — run the full `mirror + prepare + bundle` for at least one engine.
5. **Before a customer delivery** — execute the full [Air-Gap QA Checklist](#4-full-end-to-end-air-gap-qa-checklist-gcp) on a fresh GCP project + golden image where possible.

---

## 8. Quick Reference Commands

```bash
# Developer loop (fast)
go run ./cmd/aegis-cli generate --profile gcp-vllm --out /tmp/vllm && \
go run ./cmd/aegis-cli generate --profile gcp-demo --out /tmp/ollama && \
make test-local

# Full local validation after cluster bootstrap (kind or real)
NS=aegis ENGINE=auto ./scripts/validate.sh

# Air-gap proof (from inside VM after NAT removal)
kubectl -n aegis run -it --rm debug --image=curlimages/curl -- \
  curl -s http://mission-control:8080/query -d '{"prompt":"Reactor status?","max_tokens":40}'
```

---

**You now have a living testing contract for the project.**

When Phase 6 (multi-node) or Phase 7 (SBOM + signing) begins, extend the relevant sections in this file.

*Last updated: Phase 5 implementation — May 2026*