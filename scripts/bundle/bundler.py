#!/usr/bin/env python3
"""
bundler.py - Aegis Air-Gap Bundle Creator

Creates a single portable .bundle (tar.gz) containing:
- All container image tarballs
- Pre-downloaded model weights
- Rendered Kubernetes manifests
- Bootstrap scripts
- SHA-256 checksums for every included file (tamper proofing)

Usage (after running mirror-images.sh + prepare-models.sh + aegis-cli generate):
  python3 bundler.py \
      --staging ./staging \
      --manifests ./out/gcp-demo \
      --profile gcp-demo \
      --out ./aegis-v1.0-gcp-demo.bundle

The resulting .bundle can be scp'd or sneaker-netted to the target environment.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def create_bundle(staging: Path, manifests: Path, profile: str, out: Path):
    if not staging.exists():
        print(f"ERROR: staging dir not found: {staging}", file=sys.stderr)
        sys.exit(1)
    if not manifests.exists():
        print(f"ERROR: manifests dir not found: {manifests}", file=sys.stderr)
        sys.exit(1)

    bundle_name = out.name
    if not bundle_name.endswith(".bundle"):
        out = out.with_suffix(".bundle")

    print(f"==> Building Aegis bundle: {out}")
    print(f"    Staging : {staging}")
    print(f"    Manifests: {manifests}")
    print(f"    Profile : {profile}")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "aegis-bundle"
        root.mkdir(parents=True)

        # Copy key directories
        for sub in ["images", "models"]:
            src = staging / sub
            if src.exists():
                shutil.copytree(src, root / sub)
                print(f"  + copied {sub}/")

        # Copy rendered manifests
        man_dest = root / "manifests"
        shutil.copytree(manifests, man_dest)
        print("  + copied manifests/")

        # Copy any bootstrap scripts that exist next to this file or in staging
        scripts_src = Path(__file__).parent
        boot_dest = root / "scripts"
        boot_dest.mkdir()
        for sh in scripts_src.glob("*.sh"):
            shutil.copy2(sh, boot_dest / sh.name)
        # Also look for a rendered bootstrap in manifests or staging
        for candidate in [staging / "bootstrap.sh", manifests / "bootstrap.sh"]:
            if candidate.exists():
                shutil.copy2(candidate, boot_dest / "bootstrap.sh")
        print("  + copied scripts/")

        # Write bundle metadata
        meta = {
            "created_at": datetime.now(timezone.utc).isoformat(),
            "profile": profile,
            "aegis_version": "0.1.0-phase3",
            "contents": {
                "images": [p.name for p in (root / "images").glob("*") if p.is_file()],
                "models": list({p.parent.name for p in (root / "models").rglob("*") if p.is_file()}),
                "manifests": [p.name for p in (root / "manifests").glob("*.yaml")],
            },
        }
        (root / "bundle.json").write_text(json.dumps(meta, indent=2))

        # Generate comprehensive SHA256SUMS (the "verification" requirement)
        sums = []
        for dirpath, _, filenames in os.walk(root):
            for fn in filenames:
                if fn.endswith(".sha256"):
                    continue  # skip previous per-file checksums
                fp = Path(dirpath) / fn
                rel = fp.relative_to(root)
                digest = sha256_file(fp)
                sums.append(f"{digest}  {rel}")

        (root / "SHA256SUMS").write_text("\n".join(sorted(sums)) + "\n")
        print(f"  + wrote SHA256SUMS ({len(sums)} files)")

        # Create the final compressed bundle
        out.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(out, "w:gz") as tar:
            tar.add(root, arcname=".")

        # Also emit a detached checksum of the bundle itself
        bundle_sum = sha256_file(out)
        (out.with_suffix(out.suffix + ".sha256")).write_text(f"{bundle_sum}  {out.name}\n")

        size = out.stat().st_size / (1024 * 1024)
        print(f"\n==> SUCCESS: {out} ({size:.1f} MiB)")
        print(f"    Verify with:  sha256sum -c {out.name}.sha256")
        print(f"    Extract:      tar -xzf {out} -C /opt/aegis")
        return out

def main():
    ap = argparse.ArgumentParser(description="Aegis portable bundle builder")
    ap.add_argument("--staging", type=Path, default=Path("./staging"), help="Staging directory root")
    ap.add_argument("--manifests", type=Path, required=True, help="Directory produced by 'aegis-cli generate'")
    ap.add_argument("--profile", required=True)
    ap.add_argument("--out", type=Path, default=Path("./aegis-v1.bundle"))
    args = ap.parse_args()

    create_bundle(args.staging, args.manifests, args.profile, args.out)

if __name__ == "__main__":
    main()
