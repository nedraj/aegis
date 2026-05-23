# longhorn-deployment.yaml.tpl
# Basic Longhorn deployment scaffold for Phase 6 (Multi-node + Distributed Storage)
#
# This is a minimal starting point. Full production Longhorn deployment
# should be customized based on https://longhorn.io/docs/

apiVersion: v1
kind: Namespace
metadata:
  name: longhorn-system
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: longhorn
  namespace: kube-system
spec:
  repo: "https://charts.longhorn.io"
  chart: "longhorn"
  version: "1.6.0"   # Pin a known good version
  targetNamespace: longhorn-system
  valuesContent: |
    defaultSettings:
      createDefaultDiskLabeledNodes: true
      defaultDataPath: /var/lib/longhorn
      replicaSoftAntiAffinity: true
    persistence:
      defaultClass: true
      defaultClassReplicaCount: 2
---
# Optional: Simple StorageClass for Aegis model volumes
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aegis-longhorn
provisioner: driver.longhorn.io
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "30"
  fromBackup: ""
  fsType: "ext4"