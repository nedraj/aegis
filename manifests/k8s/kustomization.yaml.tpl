apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: {{ .Namespace }}

resources:
  - namespace.yaml
  {{- if eq .InferenceEngine "vllm" }}
  - vllm-deployment.yaml
  {{- else }}
  - ollama-deployment.yaml
  {{- end }}
  - mission-control-deployment.yaml
  - nvidia-device-plugin.yaml
  - zot-registry.yaml
  {{- if eq .ClusterMode "multi-node" }}
  # Longhorn for distributed storage (Phase 6)
  - longhorn-deployment.yaml
  {{- end }}

commonLabels:
  aegis.io/managed-by: "aegis-cli"
  aegis.io/profile: "{{ .ProfileName }}"
