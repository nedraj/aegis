apiVersion: v1
kind: Namespace
metadata:
  name: {{ .Namespace }}
  labels:
    aegis/project: "true"
    aegis/profile: "{{ .ProfileName }}"
