# Project Aegis: Industry Standards & Compliance Reference

This document maps the architectural decisions of Project Aegis to existing enterprise defense, military-aerospace, and cloud-native computing standards. Aligning with these frameworks ensures that the platform deployment engine adheres to rigorous, production-grade secure supply chain protocols.

---

## 1. Cloud-Native & Deployment Standards

### CNCF Air-Gapped Deliverables
The Cloud Native Computing Foundation (CNCF) provides definitive blueprints for managing cloud-native software (such as Kubernetes workloads) in environments completely detached from the public internet.
* **Core Philosophy:** Rather than relying on live, runtime installations, all container images and configurations must be compiled into standard OCI (Open Container Initiative) artifacts.
* **Project Mapping:** The Aegis package architecture mirrors this standard by pre-mirroring critical OCI images (K3s, vLLM, local registries) directly into a portable tarball structure rather than allowing arbitrary runtime fetches.

### Industry-Standard Tooling
* **Zarf (by Defense Unicorns):** A highly prominent open-source framework utilized within the U.S. Department of Defense to deliver DevSecOps capabilities to disconnected or air-gapped systems. Zarf packages cluster configurations, raw binaries, and application components into an immutable `.tar.zst` file.
* **Kurl.sh (by Replicated):** An enterprise-grade tool used to generate custom Kubernetes distribution installers for on-premise and completely offline enterprise data centers.

---

## 2. Cyber Security & Supply Chain Frameworks

### NIST SP 800-161: Cyber Supply Chain Risk Management (C-SCRM)
Published by the National Institute of Standards and Technology (NIST), this publication mandates strict verification mechanisms for data systems migrating into high-security enclaves.
* **Core Philosophy:** Every binary, configuration layer, or machine-learning model weight must possess an unalterable, cryptographically verifiable chain of custody to protect against transit-phase interception and tampering.
* **Project Mapping:** Aegis implements a deterministic validation matrix by enforcing automated SHA-256 checksum checks during the initial ingestion phase and executing pre-flight verification sequences at the deployment target before unpacking the execution layer.

### NIST SP 800-53: Security and Privacy Controls for Information Systems
This framework outlines federal baseline controls for boundary protection, infrastructure isolation, and restricted network egress.
* **Core Philosophy:** Systems operating inside sensitive data zones must utilize absolute boundary protection (such as physical air-gapping or logical network isolation) to guarantee that zero unencrypted telemetry or programmatic calls leak to public endpoints.
* **Project Mapping:** The deployment environment relies entirely on localized inference servers (vLLM running Phi-3 locally) and a containerized private image registry, entirely removing dependencies on public LLM endpoints or external container hub gateways.

---

## 3. Defense-Grade Architectural Blueprints

### DoD DevSecOps Reference Design
The United States Department of Defense outlines specific infrastructure delivery constraints designed to mitigate human configuration mistakes when deploying mission-critical systems to tactical edge points.
* **Core Philosophy:** Infrastructure must be completely declarative. System states should be derived programmatically from trusted, version-controlled source text files rather than manual, interactive environment modifications.
* **Project Mapping:** The profile-driven orchestration built into the Go-based CLI (`aegis-cli`) adheres strictly to this requirement. By passing a clean YAML profile, the generator renders exact, repeatable infrastructure state definitions using Infrastructure as Code (IaC) and embedded Helm/Kubernetes templates.
