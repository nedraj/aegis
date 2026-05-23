# Aegis Gaps Analysis (Phases 1–5)

**Date:** 2026-05-23  
**Source:** Comprehensive review by 5 independent reviewer subagents (one per phase)

This document captures the identified gaps, risks, and recommended fixes across the current Aegis implementation.

---

## Executive Summary

Aegis has a solid architectural vision and has made strong progress through Phase 5. However, the codebase is still in a **solid demo / advanced prototype** state rather than production-hardened for real air-gapped deployments.

The most critical gaps fall into three categories:

- **Air-gap Security Enforcement** (NetworkPolicy is incomplete/broken)
- **Reproducibility & Bundle Integrity** (missing verification steps, `:latest` tags)
- **Completeness of the "Foolproof" Pipeline** (IaC gaps, missing automation for key components)

---

## Immediate Priority Gaps (Must Fix Before Real Deployment or Phase 6)

### 1. NetworkPolicy Enforcement (Critical Security/Air-Gap Gap)

**Problem:**
- The only NetworkPolicy (`mission-control-deny-egress`) has a YAML structure bug that makes the inference pod allow rule overly broad.
- Inference pods (`aegis/component: inference`) have **zero egress restrictions**.
- No namespace-wide default-deny + explicit allow-list as originally planned in Phase 2.

**Impact:** A compromised inference container (or future sidecar) can reach the public internet.

**Files affected:**
- `manifests/k8s/mission-control-deployment.yaml.tpl` (lines 62–93)

**Recommended Fix:**
- Fix the YAML structure of the existing policy.
- Add a second (or combined) NetworkPolicy that restricts egress for `aegis/component: inference` pods to only DNS + (optionally) other allowed destinations.

---

### 2. Mission Control Image Not Included in Bundles

**Problem:**
- Every profile references `aegis/mission-control:latest`.
- This image is **never built or saved** during the bundle process (`mirror-images.sh`, `bundler.py`, Makefile, etc.).
- On a fresh air-gapped node with `imagePullPolicy: Never`, the pod will fail to start.

**Impact:** Breaks the core promise of a portable, self-contained `.bundle`.

**Recommended Fix:**
- Automate building and `docker save` of the Mission Control image during staging.
- Include it in `staging/images/` and update `bundler.py` + documentation.

---

### 3. No Mandatory Bundle Verification on Target

**Problem:**
- `bootstrap.sh.tpl` does not run `sha256sum -c SHA256SUMS`.
- Operator must remember to verify integrity manually after transfer.

**Impact:** Reduces trust in the air-gap delivery chain.

**Recommended Fix:**
- Add integrity verification at the very start of `bootstrap.sh.tpl` (fail fast on mismatch).

---

### 4. Pulumi IaC Does Not Deliver "Zero NAT from t=0" for Golden Images (Phase 4)

**Problem:**
- `iac/pulumi/main.go` still creates Cloud NAT and external IPs **unconditionally**, even when `use_golden_image: true`.
- Documentation (`ONBOARDING.md`, `RUNBOOK.md`) claims "no NAT created" for golden path, but code does not match.

**Impact:** The core Phase 4 promise is not fulfilled in automation.

**Recommended Fix:**
- Make NAT/router and `access_configs` conditional on `!use_golden_image`.

---

### 5. Bundle Extraction Instructions Are Inconsistent

**Problem:**
- `bundler.py` success message says `tar -xzf ... -C /opt/aegis`
- `RUNBOOK.md` says `--strip-components=1`
- These contradict each other and can break `bootstrap.sh`.

**Recommended Fix:**
- Standardize extraction method and update all references.

**Status (as of latest changes):**
- ✅ NetworkPolicy structure fixed + added `inference-deny-egress` policy in `mission-control-deployment.yaml.tpl`
- ✅ Mandatory `sha256sum -c` verification added at the top of `bootstrap.sh.tpl`
- ✅ New script `scripts/bundle/build-mission-control.sh` + `make stage-mission-control` + `make stage-all` targets
- ✅ Bundle extraction instructions standardized (`--strip-components=1`) in `bundler.py`, `RUNBOOK.md`, and bootstrap comments
- ✅ Pulumi NAT + public IP now conditional on `!useGolden` (golden images get no public exposure by default)

All 5 Immediate items from the original list have been addressed in code/docs. Some documentation propagation and end-to-end testing remain.

---

## Other Notable Gaps (High / Medium Priority)

### Reproducibility & Supply Chain
- Heavy use of `:latest` tags for all images (Ollama, vLLM, Zot, NVIDIA plugin).
- No pinning of `huggingface_hub` or model revisions during staging.
- No SBOM or image digests recorded in `bundle.json`.

### Testing & Validation
- **Zero Go unit tests** for generator, profiles, or CLI.
- **Zero Python tests** for `mission-control/app.py`.
- No automated validation of rendered NetworkPolicies or bundle contents.

### Technical Debt & Maintainability
- Engine selection logic is hardcoded (if/else + string matching) in multiple places.
- Legacy `Ollama*` fields pollute `RenderContext` even for vLLM.
- Many profile fields are parsed but not used by the generator (`k3s.version`, `bundle.*`, etc.).
- `gcp-vllm` on real T4 hardware is not yet turnkey (memory pressure + quantization workflow is manual).

### Phase 6 Readiness
- Multi-node profile (`gcp-multi.yaml`) and generator scaffolding exist, but:
  - No Longhorn deployment template.
  - No multi-node bootstrap / join logic.
  - No support for shared model storage (hostPath will not work across nodes).
  - Pulumi still only creates single instances.

### Documentation Drift
- Several claims in `ONBOARDING.md` and `RUNBOOK.md` about "true zero-NAT from first packet" do not match current Pulumi behavior.

---

## Recommended Immediate Action Plan

1. **Fix NetworkPolicy** (highest security priority)
2. **Automate Mission Control image into bundle pipeline**
3. **Add `sha256sum -c` verification in `bootstrap.sh.tpl`**
4. **Make NAT + public IP conditional in Pulumi for golden images**
5. **Standardize bundle extraction and fix contradictory docs**

### Progress on Immediate Items (as of this session)

- ✅ NetworkPolicy for both MC and inference pods added/fixed
- ✅ Mandatory bundle integrity check in `bootstrap.sh.tpl`
- ✅ Mission Control image build automation (`build-mission-control.sh` + Makefile targets)
- ✅ Extraction standardization (`--strip-components=1` everywhere)
- ✅ Pulumi now creates true zero-NAT instances for golden images (no NAT, no public IP by default)

### Next Recommended Wave (High Value) — Progress This Session

- ✅ Pinned images + image manifest in `mirror-images.sh` and `bundler.py`
- ✅ Basic Go unit test added for generator (`internal/generator/generator_test.go`)
- ✅ Started Longhorn + multi-node scaffolding (`longhorn-deployment.yaml.tpl`, conditional includes in kustomization + bootstrap)
- Improved reproducibility notes in bundle metadata

Still open (mostly addressed in this session):
- Python tests for Mission Control (`mission-control/test_app.py` added)
- Engine handling generalized (`internal/generator/engines.go` + registry)

Remaining before full production readiness:
- Comprehensive test coverage + CI
- Real hardware validation for vLLM/T4
- Full Phase 6 multi-node + Longhorn implementation
- Add post-generate / post-bundle validation checks
- Full Phase 6 (Longhorn HA, multi-node join logic, Pulumi multi-instance support)

---

*This document was generated from the combined findings of 5 independent phase-specific reviewer subagents.*