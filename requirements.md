# Project Aegis: Air-Gapped AI Platform Deployment Engine (GCP Demo)

## 1. Project Vision
Project Aegis is a proof-of-concept demonstration of a deterministic, profile-driven deployment engine. It is designed to solve the "last mile" problem of AI infrastructure: deploying a fully functional, low-power AI inference stack into environments with restricted or zero internet access (Air-Gap simulation).

For this demo, we use **Google Cloud Platform (GCP)** as our substrate, leveraging low-power, cost-effective resources to simulate a field-deployed "Special Programs" edge node.

## 2. Technical Core Requirements

### 2.1 Profile-Driven Orchestration (The "Generator")
* **Engine:** A Golang-based CLI (`aegis-cli`) that uses YAML profiles to render deployment manifests.
* **Deterministic Logic:** The CLI must bake all Helm charts and Kubernetes manifests into its binary using `go:embed`.
* **Target Profiles:**
    * `gcp-demo`: Deploys to a single GCE instance with a T4 GPU.
    * `airgap-sim`: Generates a portable `.bundle` file containing all binaries, images, and weights.

### 2.2 Low-Power AI Stack (The "Workflow")
* **Model:** **Phi-3-Mini-4k-Instruct** (3.8B parameters). Chosen for its high reasoning-to-power ratio and ability to run on commodity hardware/smaller GPUs.
* **Inference Server:** **vLLM** or **Ollama** (Containerized).
* **Workflow Integration:** A simple Python-based "Mission Control" API that accepts queries and routes them to the local model without hitting external APIs (OpenAI/Gemini).

### 2.3 Dependency Bundling (The "Foolproof" Pipeline)
* **Container Mirroring:** A script to pull and export OCI images for:
    * K3s (Lightweight Kubernetes)
    * NVIDIA Device Plugin
    * Local Image Registry (Zot)
    * The Inference Server
* **Verification:** Automatic SHA-256 checksum generation for every file in the bundle.

## 3. GCP Deployment Architecture (Demo Substrate)

### 3.1 Infrastructure Layer (IaC)
* **Tool:** Pulumi (Go) or Terraform.
* **Compute:** `n1-standard-4` instance with 1x **NVIDIA Tesla T4** GPU.
* **OS:** Ubuntu 22.04 LTS (Minimal).
* **Networking:** Isolated VPC with Cloud NAT disabled after the initial staging phase to simulate the air-gap.

### 3.2 The Provisioning Workflow
1.  **Stage 1 (Connected):** CLI pulls `Phi-3` weights, Docker images, and K3s binaries to a local `staging/` directory.
2.  **Stage 2 (Bundle):** CLI compresses `staging/` into `aegis-v1.bundle`.
3.  **Stage 3 (Deploy):** The IaC tool creates the GCP VM and uses `cloud-init` to:
    * Mount a persistent disk containing the `.bundle`.
    * Install the local NVIDIA drivers.
    * Hydrate the local container registry from the bundle.
    * Bootstrap K3s pointing to the local registry.

## 4. End-to-End AI Workflow Validation
The project is successful if, upon deployment, the following can be executed via a local curl command inside the VPC:
1.  **Hardware Check:** `nvidia-smi` confirms GPU visibility within the K3s pod.
2.  **Model Loading:** The inference server loads `Phi-3` from the local persistent volume (not the internet).
3.  **Deterministic Inference:** The model answers a technical "Mission Update" query without any egress traffic to the public internet.

## 5. Repository Structure
```text
/aegis
  /cmd/aegis-cli        # Go source for the generator
  /internal/profiles    # YAML profile templates
  /scripts/bundle       # Python/Bash scripts for image mirroring
  /iac/pulumi           # Infrastructure as Code for GCP
  /manifests/k8s        # Embedded K8s templates (vLLM, Registry, Mission Control)
  /docs                 # Architectural trade-off documents
  requirements.md       # This file
  ```
