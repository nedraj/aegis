apiVersion: apps/v1
kind: Deployment
metadata:
  name: mission-control
  namespace: {{ .Namespace }}
  labels:
    app: mission-control
    aegis/component: api
spec:
  replicas: {{ .MissionControlReplicas }}
  selector:
    matchLabels:
      app: mission-control
  template:
    metadata:
      labels:
        app: mission-control
    spec:
      containers:
        - name: mission-control
          image: {{ .MissionControlImage }}
          imagePullPolicy: {{ .ImagePullPolicy }}
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: INFERENCE_ENGINE
              value: "{{ .InferenceEngine }}"
            - name: INFERENCE_URL
              value: "http://{{ .InferenceServiceName }}.{{ .Namespace }}.svc.cluster.local:{{ .InferencePort }}"
            - name: MODEL_NAME
              value: "{{ .ModelName }}"
          resources:
            requests:
              cpu: "100m"
              memory: "256Mi"
            limits:
              cpu: "1"
              memory: "512Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: mission-control
  namespace: {{ .Namespace }}
spec:
  selector:
    app: mission-control
  ports:
    - port: 8080
      targetPort: 8080
      name: http
  type: ClusterIP
---
apiVersion: v1
kind: NetworkPolicy
metadata:
  name: mission-control-deny-egress
  namespace: {{ .Namespace }}
spec:
  podSelector:
    matchLabels:
      app: mission-control
  policyTypes:
    - Egress
  egress:
    # Only allow DNS and traffic to the inference backend (ollama or vllm) inside namespace.
    # Phase 5: uses common aegis/component label + engine-specific port.
    - to:
        - namespaceSelector:
            matchLabels:
              aegis/project: "true"
        - podSelector:
            matchLabels:
              aegis/component: inference
      ports:
        - protocol: TCP
          port: {{ .InferencePort }}
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
