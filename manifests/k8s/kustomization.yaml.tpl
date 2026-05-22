apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: {{ .Namespace }}

resources:
  - namespace.yaml
  - ollama-deployment.yaml
  - mission-control-deployment.yaml
  - nvidia-device-plugin.yaml
  - zot-registry.yaml

commonLabels:
  aegis.io/managed-by: "aegis-cli"
  aegis.io/profile: "{{ .ProfileName }}"
