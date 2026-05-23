package main

/*
Pulumi Go program for Project Aegis - GCP Demo Substrate (Phase 3)

This provisions:
  - A VPC with private subnet (Cloud NAT enabled only for the bootstrap window)
  - Firewall rules for SSH + internal traffic
  - n1-standard-4 + 1x NVIDIA T4 GPU instance (Ubuntu 22.04)
  - A large Persistent Disk that will hold the .bundle (populated out-of-band via gcloud scp or a data-populator VM)
  - cloud-init user-data that:
      * mounts the bundle disk
      * installs NVIDIA drivers + CUDA (requires the NAT window)
      * installs K3s
      * runs the bootstrap.sh from the bundle (imports images to containerd, starts k3s, applies manifests)

After the first successful bootstrap you manually (or via a follow-up Pulumi step) remove the NAT
to simulate the air-gap, then validate that inference still works.

Usage:
  cd iac/pulumi
  pulumi stack init gcp-demo
  pulumi config set gcp:project YOUR_PROJECT
  pulumi up
*/

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v7/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		// --- Config ---
		project := ctx.Config().Require("gcp:project")
		region := ctx.Config().Get("gcp:region")
		if region == "" {
			region = "us-central1"
		}
		zone := ctx.Config().Get("gcp:zone")
		if zone == "" {
			zone = region + "-a"
		}

		// Phase 4: Support for pre-baked golden image (true zero-NAT)
		useGolden := ctx.Config().GetBool("use_golden_image")
		goldenFamily := ctx.Config().Get("custom_image_family")
		if goldenFamily == "" {
			goldenFamily = "aegis-golden-ubuntu-2204-nvidia-k3s"
		}

		// --- Network (isolated after bootstrap) ---
		vpc, err := compute.NewNetwork(ctx, "aegis-vpc", &compute.NetworkArgs{
			Project:                 pulumi.String(project),
			AutoCreateSubnetworks:   pulumi.Bool(false),
			Description:             pulumi.String("Aegis air-gap demo VPC - NAT removed after staging"),
		})
		if err != nil {
			return err
		}

		subnet, err := compute.NewSubnetwork(ctx, "aegis-subnet", &compute.SubnetworkArgs{
			Project:     pulumi.String(project),
			Network:     vpc.SelfLink,
			Region:      pulumi.String(region),
			IpCidrRange: pulumi.String("10.42.0.0/16"),
			Description: pulumi.String("Private subnet for Aegis K3s node"),
		})
		if err != nil {
			return err
		}

		// Cloud NAT + public IP are only needed for the non-golden path (Phase 3 style)
		// When useGolden is true, we want true zero-NAT from first boot.
		if !useGolden {
			router, err := compute.NewRouter(ctx, "aegis-router", &compute.RouterArgs{
				Project: pulumi.String(project),
				Region:  pulumi.String(region),
				Network: vpc.SelfLink,
			})
			if err != nil {
				return err
			}

			_, err = compute.NewRouterNat(ctx, "aegis-nat", &compute.RouterNatArgs{
				Project:                       pulumi.String(project),
				Region:                        pulumi.String(region),
				Router:                        router.Name,
				NatIpAllocateOption:           pulumi.String("AUTO_ONLY"),
				SourceSubnetworkIpRangesToNat: pulumi.String("ALL_SUBNETWORKS_ALL_IP_RANGES"),
			})
			if err != nil {
				return err
			}
		}

		// --- Firewall ---
		_, err = compute.NewFirewall(ctx, "aegis-allow-ssh", &compute.FirewallArgs{
			Project:     pulumi.String(project),
			Network:     vpc.SelfLink,
			Description: pulumi.String("Allow SSH from anywhere (demo) - tighten in production"),
			Allows: compute.FirewallAllowArray{
				&compute.FirewallAllowArgs{
					Protocol: pulumi.String("tcp"),
					Ports:    pulumi.StringArray{pulumi.String("22")},
				},
			},
			SourceRanges: pulumi.StringArray{pulumi.String("0.0.0.0/0")},
		})
		if err != nil {
			return err
		}

		// --- GPU Instance ---
		// Phase 3 (vanilla Ubuntu): heavy startup script that installs drivers + K3s (needs NAT window)
		// Phase 4 (golden image): tiny script. Drivers + K3s already present. True zero-NAT possible.
		var startup pulumi.String
		if useGolden {
			startup = pulumi.String(`#!/bin/bash
set -e
echo "[aegis-golden] Booting hardened custom image (Phase 4) — zero internet required from t=0"

mkdir -p /opt/aegis
if [ -b /dev/sdb ]; then
  mount /dev/sdb /opt/aegis 2>/dev/null || true
fi

if [ -x /opt/aegis/scripts/bootstrap.sh ]; then
  /opt/aegis/scripts/bootstrap.sh
else
  echo "[aegis] Waiting for operator to deliver .bundle to /opt/aegis"
fi

echo "[aegis-golden] Bootstrap finished. This node never contacted the public internet."
`)
		} else {
			startup = pulumi.String(`#!/bin/bash
set -e
echo "[aegis-cloud-init] Starting Aegis bootstrap on $(hostname) (vanilla image - Phase 3)"

apt-get update -y
apt-get install -y curl wget ca-certificates gnupg lsb-release

# NVIDIA drivers + toolkit (the step that forces NAT in Phase 3)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -y
apt-get install -y nvidia-driver-535-server nvidia-container-toolkit

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -

mkdir -p /opt/aegis
if [ -b /dev/sdb ]; then
  mount /dev/sdb /opt/aegis 2>/dev/null || true
fi

if [ -x /opt/aegis/scripts/bootstrap.sh ]; then
  /opt/aegis/scripts/bootstrap.sh
fi

echo "[aegis-cloud-init] Bootstrap complete. Remove NAT for air-gap validation."
`)
		}

		instance, err := compute.NewInstance(ctx, "aegis-edge-node", &compute.InstanceArgs{
			Project:       pulumi.String(project),
			Zone:          pulumi.String(zone),
			MachineType:   pulumi.String("n1-standard-4"),
			MinCpuPlatform: pulumi.String("Intel Haswell"),
			BootDisk: &compute.InstanceBootDiskArgs{
				InitializeParams: &compute.InstanceBootDiskInitializeParamsArgs{
					Image: pulumi.String(func() string {
						if useGolden {
							return "projects/" + project + "/global/images/family/" + goldenFamily
						}
						return "ubuntu-os-cloud/ubuntu-2204-lts"
					}()),
					Size: pulumi.Int(50),
				},
			},
			AttachedDisks: compute.InstanceAttachedDiskArray{
				&compute.InstanceAttachedDiskArgs{
					Source:    pulumi.String("/aegis-bundle-disk"), // created separately or by hand for large bundle
					DeviceName: pulumi.String("bundle-disk"),
				},
			},
			NetworkInterfaces: compute.InstanceNetworkInterfaceArray{
				&compute.InstanceNetworkInterfaceArgs{
					Subnetwork: subnet.SelfLink,
					// Only give a public IP on the non-golden path.
					// Golden image path should have zero public exposure from the start.
					AccessConfigs: func() compute.InstanceNetworkInterfaceAccessConfigArray {
						if useGolden {
							return nil // No public IP for true zero-NAT golden images
						}
						return compute.InstanceNetworkInterfaceAccessConfigArray{
							&compute.InstanceNetworkInterfaceAccessConfigArgs{},
						}
					}(),
				},
			},
			GuestAccelerators: compute.InstanceGuestAcceleratorArray{
				&compute.InstanceGuestAcceleratorArgs{
					Type:  pulumi.String("nvidia-tesla-t4"),
					Count: pulumi.Int(1),
				},
			},
			Metadata: pulumi.StringMap{
				"startup-script": startup,
			},
			MetadataStartupScript: startup, // also as direct field for older images
			ServiceAccount: &compute.InstanceServiceAccountArgs{
				Email: pulumi.String("default"),
				Scopes: pulumi.StringArray{
					pulumi.String("https://www.googleapis.com/auth/cloud-platform"),
				},
			},
			Tags: pulumi.StringArray{pulumi.String("aegis-edge")},
		})
		if err != nil {
			return err
		}

		// Outputs for the operator
		ctx.Export("instanceName", instance.Name)
		ctx.Export("instanceIP", instance.NetworkInterfaces.Index(pulumi.Int(0)).AccessConfigs().Index(pulumi.Int(0)).NatIp())
		ctx.Export("vpc", vpc.Name)
		ctx.Export("note", pulumi.String("After first boot: gcloud compute scp aegis-v1.bundle <instance>:/opt/aegis/  then ssh and run the bootstrap manually if cloud-init did not. Then delete the NAT for true air-gap demo."))

		fmt.Printf("Aegis GCP IaC stack prepared for project %s\n", project)
		return nil
	})
}
