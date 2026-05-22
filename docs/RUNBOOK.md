# Aegis Runbook — End-to-End Demo (GCP T4)

This document gives the **exact commands** an operator runs on a connected workstation to produce a working air-gapped Phi-3 inference node on GCP.

> Prerequisites
> - Go 1.23+
> - Docker (with ability to pull public images)
> - Python 3.11+
> - `gcloud` authenticated + Pulumi CLI
> - GCP project with `n1-standard-4` + T4 GPU quota in a zone that has T4s (us-central1-a, etc.)

---

## 1. One-time workstation setup

```bash
git clone .../aegis.git
cd aegis
go build -o aegis-cli ./cmd/aegis-cli
```

---

## 2. Phase 1 + 2 — Generate manifests for the target profile

```bash
./aegis-cli generate --profile gcp-demo --out ./out/gcp-demo
```

You now have ready-to-apply (or ready-to-bundle) K8s YAMLs + `bootstrap.sh`.

---

## 3. Phase 3 — Create the portable bundle (the "foolproof" part)

```bash
# 3a. Pull & export every container image (≈ 3-4 GB total)
bash scripts/bundle/mirror-images.sh ./staging

# 3b. Pull Phi-3-mini weights via Ollama into the staging tree (≈ 2.2 GB)
bash scripts/bundle/prepare-models.sh ./staging

# 3c. Assemble the single distributable artifact + full SHA-256 manifest
./aegis-cli bundle \
    --profile gcp-demo \
    --manifests ./out/gcp-demo \
    --staging ./staging \
    --out ./aegis-gcp-demo-v1.bundle
```

Result:
- `aegis-gcp-demo-v1.bundle` (tar.gz)
- `aegis-gcp-demo-v1.bundle.sha256`

Verify anytime:
```bash
tar -xOf aegis-gcp-demo-v1.bundle ./aegis-bundle/SHA256SUMS | sha256sum -c -
```

---

## 4. Provision the GCP substrate (IaC)

```bash
cd iac/pulumi

# First time
pulumi stack init gcp-demo
pulumi config set gcp:project YOUR_PROJECT_ID
pulumi config set gcp:zone us-central1-a

pulumi up   # creates VPC, NAT, T4 VM, firewall, startup-script hook
```

After `pulumi up` you will get the external IP of the VM.

**Important:** The instance is created with a Cloud NAT so the first boot can:
- apt-get update
- install NVIDIA drivers + container toolkit
- install K3s

The startup script prints: *"Remove NAT now for air-gap simulation."*

---

## 5. Transfer the bundle onto the VM (the air-gap transfer step)

While the VM still has outbound internet (NAT present):

```bash
# From your workstation
gcloud compute scp \
  ./aegis-gcp-demo-v1.bundle \
  aegis-edge-node:/tmp/ \
  --zone us-central1-a

# SSH in
gcloud compute ssh aegis-edge-node --zone us-central1-a
```

Inside the VM:

```bash
sudo mkdir -p /opt/aegis
sudo tar -xzf /tmp/aegis-gcp-demo-v1.bundle -C /opt/aegis --strip-components=1

# Now run the bootstrap that was rendered for this profile
sudo /opt/aegis/scripts/bootstrap.sh
```

The script will:
- Import every image tar into containerd
- Start K3s
- `kubectl apply` the whole stack (ollama + mission-control + device-plugin + zot)
- Mount the model volume so Phi-3 never touches the net

---

## 6. Validation (the three success criteria from requirements.md)

All commands below are run **from inside the VM** (or via `kubectl exec`).

### 6.1 Hardware check — GPU visible to K3s

```bash
kubectl -n aegis exec -it deploy/ollama -- nvidia-smi
# Expected: Tesla T4, 15 GiB, CUDA version, no errors
```

### 6.2 Model loaded from local disk only

```bash
kubectl -n aegis exec -it deploy/ollama -- ls -lh /root/.ollama/models/models/manifests/registry.ollama.ai/library/phi3
# You should see the blob that was pre-staged in the bundle — no download occurred.
```

### 6.3 Deterministic inference with zero egress

```bash
# Port-forward or use the ClusterIP from inside a debug pod
kubectl -n aegis run -it --rm debug --image=curlimages/curl -- /bin/sh

# Inside the debug shell:
curl -s -X POST http://mission-control:8080/query \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Provide a one-line status of the forward sensor array and any anomalies detected in the last 6 hours."}' \
  | jq .
```

Expected output shape:
```json
{
  "response": "MISSION UPDATE: Forward sensor array nominal. Minor thermal variance on array 3 within acceptable parameters. All other systems green.",
  "model": "phi3:mini",
  "backend": "ollama-local",
  ...
}
```

**To prove the air-gap:**
1. On the GCP console or via gcloud, **delete the Cloud NAT** (or remove the VM's external IP).
2. Repeat the exact `/query` call above.
3. The call must still succeed and return a coherent answer.
4. (Optional) Run `tcpdump` or check VPC Flow Logs — you will see **zero** flows to `*.openai.com`, `*.googleapis.com` (except the GCP metadata service which is unavoidable on GCE).

---

## 7. Phase 4 — True Zero-NAT Deployment (Recommended)

If you have built the golden image (see `scripts/image-bake/README.md` and `docs/ONBOARDING.md`), switch to the hardened profile:

```bash
./aegis-cli generate --profile gcp-hardened --out ./out/gcp-hardened

# Then build the bundle as usual
./aegis-cli bundle --profile gcp-hardened ...
```

In `iac/pulumi`:

```bash
pulumi config set use_golden_image true
pulumi config set custom_image_family aegis-golden-ubuntu-2204-nvidia-k3s
pulumi up
```

**Result**: The VM is created with **no Cloud NAT** and the startup script is only a few lines. The entire node can boot with zero external connectivity.

---

## 8. Cleanup

```bash
# From the pulumi dir
pulumi destroy
```

---

## Troubleshooting (common)

- **No GPU in pod**: The NVIDIA device plugin must run **after** the drivers are installed on the host. Reboot the VM once after driver install if `nvidia-smi` on host fails.
- **ImagePullBackOff**: The `bootstrap.sh` did not finish importing the tars. Re-run it.
- **Ollama says "model not found"**: The model tar from `prepare-models.sh` was not extracted to `/opt/aegis/models` before the pod started. The hostPath volume will pick it up on next pod restart.
- **Python bundler complains**: `pip install -r mission-control/requirements.txt` then run the bundler again.

---

## Local (no-GPU) development of Mission Control

```bash
cd examples
docker compose -f docker-compose.local.yml up --build
# In another terminal:
curl -X POST http://localhost:8080/query \
  -d '{"prompt":"Mission status?"}'
```

This spins up real Ollama + the exact same FastAPI code you will ship in the bundle.

---

**You have now completed a full Phase 1-2-3 implementation of Project Aegis.**

The only remaining real-world hardening items (Phase 4) are:
- Baking a custom GCP image that already contains the NVIDIA drivers + K3s so the VM can boot with **zero** NAT from minute zero.
- Cryptographic signing of the `.bundle` + `cosign` / `rekor` verification on the target.
- Multi-node profile + storage for larger models.

All core requirements from `requirements.md` are satisfied by the code in this repository.
