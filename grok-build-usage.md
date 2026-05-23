# Grok Build TUI — Effective Usage Patterns (Aegis Edition)

**Purpose:** This document captures lessons learned from working on Project Aegis with Grok Build. It turns ad-hoc prompting into repeatable, high-leverage practices.

**Audience:** Anyone working on long-lived, multi-phase engineering projects with the Grok TUI (especially mixed-language codebases with infrastructure concerns).

---

## 1. Core Mindset Shift

Treat Grok less like a "smart autocomplete" and more like a **junior-to-mid-level engineering collaborator** that can:

- Maintain long context across sessions
- Delegate to specialized subagents
- Follow project-specific rules
- Use codified workflows (skills)

The highest returns come from **reducing repeated context** and **increasing structure**.

---

## 2. Prompting Patterns That Work Well

### The High-Leverage Prompt Template

Use this structure for non-trivial tasks:

```markdown
Context:     [Reference existing docs, decisions, or artifacts]
Goal:        [What "done" looks like — be specific]
Constraints: [Scope limits, things NOT to do, files to avoid touching]
Success Criteria: [How we will verify it worked]
Process:     [Optional: use plan mode, maintain todo list, spawn subagents, etc.]
Output:      [Specific files or artifacts expected]
```

**Example (Aegis Phase 5 style):**
> Context: Refer to PLAN.md Phase 5 section and the current generator + mission-control code.
> Goal: Add first-class vLLM support alongside Ollama.
> Constraints: Do not modify the existing ollama-deployment.yaml or prepare-models.sh behavior in this pass. Keep all current profiles working.
> Success Criteria: `aegis-cli generate --profile gcp-vllm` produces valid manifests; Mission Control can talk to either backend via /v1; TESTING.md is updated.
> Process: First enter plan mode, then implement after approval.
> Output: New vllm-deployment.yaml.tpl, updated generator, unified Mission Control, and TESTING.md.

### Other Strong Patterns

| Pattern | When to Use | Example |
|---------|-------------|---------|
| **Explicit Scope + "Do not touch"** | Any change that could have side effects | "Only touch the generator and new vllm template. Do not change bootstrap.sh yet." |
| **Deliverable-first** | Most tasks | "Capture the plan in `docs/phase-5-plan.md`" |
| **Success criteria upfront** | Anything that needs verification | "We are done when `make test-phase5` passes and validate.sh works for both engines." |
| **Reference previous decisions** | Long-running projects | "Use the same pattern we established in TESTING.md for engine detection." |

---

## 3. When to Use Specific Grok Features

### Plan Mode (High Value for Ambiguous Work)

**Use when:**
- Multiple reasonable architectures exist
- High risk of rework (new major abstraction, auth, data pipeline, etc.)
- You want to discuss trade-offs before code is written

**How to invoke:**
- Say: "Before coding, enter plan mode and produce a detailed implementation plan."
- Or let Grok auto-trigger when it detects ambiguity.

**Output:** A `plan.md` in the current session directory that you must approve before implementation begins.

### Subagents & Personas (Parallel Work)

Instead of one long context doing everything, delegate:

- `explore` subagent → deep codebase research (read-only)
- `plan` subagent → produce implementation plan
- `implementer` persona → writes code + runs builds
- `reviewer` persona → structured code review
- `test-writer` persona → adds tests

**Example prompt:**
> "Spawn an `explore` subagent to research how other projects integrate vLLM in air-gapped K8s, then spawn an `implementer` to code the deployment manifest."

### Built-in Skills (Codified Workflows)

Prefer invoking skills over describing the process every time:

- `/implement` — Full build + multi-reviewer loop
- `/review` — Professional code review
- `/check` — Verification agent (builds, tests, end-to-end correctness)
- `best-of-n` — Try multiple approaches in parallel
- `check-work` / `self-verify`

**Rule of thumb:** If you're typing "review the changes" or "make sure the tests pass", consider calling the skill instead.

### Memory vs Session History

| Tool | Purpose | When to Use |
|------|---------|-------------|
| **Session** (automatic) | Full conversation + file snapshots for this chat | Normal work, resume with `/load` |
| **Workspace Memory** (`~/.grok/memory/.../MEMORY.md`) | Cross-session facts, decisions, conventions | Major milestones — use `/flush` |
| **Project Rules** (AGENTS.md) | Always-on instructions for the repo | Invest once, benefit forever |

**Recommendation:** At the end of every major phase (or before a long break), run:

```
/flush
```

This pushes key decisions into persistent memory.

---

## 4. Session Hygiene (Long-Lived Projects)

For sessions that span days/weeks on the same project:

1. **Periodic compaction**
   ```bash
   /compact keep the Phase 5 architecture decisions, TESTING.md structure, and profile conventions
   ```

2. **Before major breaks**
   - `/session-info` (note the ID)
   - `/flush`
   - `/compact`

3. **Resuming**
   - Preferred: Launch `grok` in the directory → pick from welcome screen
   - Or `/load`

4. **Starting fresh when context is polluted**
   - `/new`

---

## 5. Investing in the Project (Highest Long-Term ROI)

### 5.1 Create an AGENTS.md (or Claude.md / AGENT.md)

This is the single best thing you can do for any project you work on repeatedly with Grok.

**Location:** Root of the repo (and optionally in subdirectories).

**What to put in it:**
- Build, test, and validation commands
- Code organization conventions
- How to extend the generator / add a new profile
- Air-gap safety rules
- "Always update TESTING.md when adding significant capability"
- Preferred patterns (e.g., "never hardcode ports — derive from RenderContext")
- Things the agent should *never* do

Once it exists, your prompts can become dramatically shorter while still getting consistent, high-quality output.

### 5.2 Create Custom Skills

For repetitive workflows specific to Aegis, encode them as skills in `.grok/skills/` or `~/.grok/skills/`.

Examples worth creating:
- `add-profile` — scaffolding a new deployment profile
- `update-validation` — extending TESTING.md + validate.sh
- `phase-review` — structured review at the end of a phase

### 5.3 Maintain TESTING.md as Living Documentation

Every time you add a non-trivial feature, update the test matrix and checklist. This compounds: future prompts can just say "follow the process in TESTING.md".

---

## 6. Quick Reference Cheat Sheet

| Situation | Recommended Prompt / Action |
|-----------|-----------------------------|
| Ambiguous or high-risk change | "Enter plan mode first" |
| Complex multi-step implementation | `/implement` or "use the implement skill with 2 reviewers" |
| Need code review | `/review` or spawn `reviewer` subagent |
| Want options explored | `best-of-n` skill |
| Verification after changes | `/check` or "run the check skill" |
| Major milestone reached | `/flush` |
| Session feels bloated | `/compact keep ...` |
| Want to start clean | `/new` |
| Need to see current session details | `/session-info` |
| Resuming later | Launch `grok` or use `/load` |

---

## 7. Anti-Patterns to Avoid

- Vague goals ("make the vLLM stuff work")
- No constraints ("add Phase 5")
- Describing a workflow you could invoke as a skill
- Never using Plan Mode on anything bigger than a few files
- Letting sessions grow for days without compaction or flushing
- Repeating the same project conventions in every prompt instead of putting them in AGENTS.md

---

## 8. Aegis-Specific Conventions (Add to AGENTS.md Later)

- Generator changes must support both ollama and vllm paths without breaking existing profiles.
- Any new inference engine must go through the unified `INFERENCE_ENGINE` / `INFERENCE_URL` variables in Mission Control.
- All new functionality must have corresponding entries in TESTING.md (test matrix + E2E checklist).
- Validate using `make test-phase5` + the engine-aware `scripts/validate.sh`.
- Prefer engine detection via labels or deployment names over hard-coded pod names where possible.

---

**This document should evolve.** After every major phase of work, review what prompting patterns worked well and capture the new lessons here.

*Captured from real Aegis Phase 5 development session — May 2026*