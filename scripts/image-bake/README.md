# Phase 4: Golden Image Baking (True Zero-NAT Boot)

This directory contains everything needed to build a **custom GCP machine image** that already contains:

- NVIDIA Tesla T4 drivers (535 server branch)
- NVIDIA Container Toolkit
- K3s (pre-installed, starts on demand)
- Aegis directory layout + helper user

With this image, the VM can boot in a **completely air-gapped network** (no Cloud NAT at all).

## Quick Start

```bash
cd scripts/image-bake/packer

# 1. Install Packer (if not present)
# https://developer.hashicorp.com/packer/install

# 2. Build the golden image (takes 15-25 minutes)
packer init .
packer build -var="project_id=YOUR_GCP_PROJECT" gcp-aegis-golden.pkr.hcl

# 3. Note the output image family: aegis-golden-ubuntu-2204-nvidia-k3s
```

## Using the Golden Image in Pulumi

See the updated [iac/pulumi/main.go](../iac/pulumi) — it now supports a `custom_image_family` variable.

When set, the instance will be created from your pre-baked image and the cloud-init becomes extremely small (just extract bundle + run bootstrap).

## Why This Matters

Without the golden image (Phase 3):
- VM needs Cloud NAT for driver + apt + k3s install
- Operator must wait for NVIDIA install before the bundle step

With the golden image (Phase 4):
- Boot with **zero external routes**
- `bootstrap.sh` runs in < 90 seconds
- True "Special Programs" field deployment simulation

## Next Steps After Building Image

1. Update your Pulumi config:
   ```bash
   pulumi config set custom_image_family aegis-golden-ubuntu-2204-nvidia-k3s
   ```

2. `pulumi up` — the VM will now use your hardened image.

3. Transfer only the `.bundle` — no driver installation ever touches the internet.
