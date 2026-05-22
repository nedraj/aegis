# Packer configuration for Aegis Golden Image (Phase 4)
# Builds a custom GCP image with NVIDIA drivers + K3s pre-installed.
# This enables true zero-internet boot for the air-gapped demo.
#
# Usage:
#   cd scripts/image-bake/packer
#   packer init .
#   packer build -var="project_id=YOUR_PROJECT" gcp-aegis-golden.pkr.hcl

packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "~> 1.1"
    }
  }
}

variable "project_id" {
  type    = string
  description = "GCP project ID where the image will be created"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "image_family" {
  type    = string
  default = "aegis-golden-ubuntu-2204-nvidia-k3s"
}

source "googlecompute" "aegis_golden" {
  project_id   = var.project_id
  zone         = var.zone
  machine_type = "n1-standard-4"

  # Use a T4 accelerator during image build so NVIDIA drivers install cleanly
  accelerator_type   = "nvidia-tesla-t4"
  accelerator_count  = 1
  on_host_maintenance = "TERMINATE"

  source_image_family = "ubuntu-2204-lts"
  disk_size           = 50
  disk_type           = "pd-ssd"

  image_name        = "aegis-golden-ubuntu-2204-nvidia-k3s-{{timestamp}}"
  image_family      = var.image_family
  image_description = "Aegis hardened golden image - Ubuntu 22.04 + NVIDIA 535 + K3s + pre-cached components. Enables true air-gap boot."

  ssh_username = "packer"
}

build {
  sources = ["source.googlecompute.aegis_golden"]

  # 1. Update system + install base prerequisites
  provisioner "shell" {
    script = "${path.root}/../provisioners/01-base-packages.sh"
  }

  # 2. Install NVIDIA drivers + CUDA + Container Toolkit (the heavy part)
  provisioner "shell" {
    script = "${path.root}/../provisioners/02-nvidia-drivers.sh"
  }

  # 3. Install K3s (single-node mode, ready for airgap)
  provisioner "shell" {
    script = "${path.root}/../provisioners/03-install-k3s.sh"
  }

  # 4. Prepare Aegis directories and helper scripts
  provisioner "shell" {
    script = "${path.root}/../provisioners/04-aegis-prep.sh"
  }

  # 5. Clean up and optimize image size
  provisioner "shell" {
    script = "${path.root}/../provisioners/99-cleanup.sh"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
