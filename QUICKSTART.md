# Aegis — 5-Minute Explainer

> **What is this project in one minute?**

## The Problem

You want to run a real AI model (like Phi-3) in a place where **there is no internet** — for example, a secure facility, a ship, or a remote site.

Downloading models or containers at runtime is not allowed.

## The Solution

Aegis lets you:

1. Define what you want in a simple YAML file (a "profile")
2. Automatically generate all the Kubernetes files you need
3. Package the AI model + all container images into **one portable file** (`.bundle`)
4. Copy that single file into the restricted environment
5. Run a script that sets everything up locally

After that, the AI keeps working **even if you unplug the network cable**.

## Core Idea (Simplified)

```
Your Laptop (with internet)
        ↓
   aegis-cli bundle
        ↓
   One magic file (aegis.bundle)
        ↓
   Sneakernet / USB
        ↓
   Locked-down machine (no internet)
        ↓
   Run bootstrap.sh → AI is now running locally
```

## Quick Try (Developer)

```bash
# 1. Build the tool
go build -o aegis-cli ./cmd/aegis-cli

# 2. See what "setups" exist
./aegis-cli profiles list

# 3. Generate files for a demo
./aegis-cli generate --profile gcp-demo --out ./out/gcp-demo
```

That's it. You now have real Kubernetes manifests ready to use.

## Want More?

- **I want to actually run this** → [docs/ONBOARDING.md](docs/ONBOARDING.md)
- **I want the full picture** → [README.md](README.md)
- **I want to understand the long-term plan** → [docs/PLAN.md](docs/PLAN.md)
- **I work with AI agents a lot** → [grok-build-tutorial.md](grok-build-tutorial.md)

---

**One sentence summary:**

*Aegis is a toolkit that packages an entire AI system (model + containers + orchestration) into a single transferable bundle so it can run reliably with zero internet.*