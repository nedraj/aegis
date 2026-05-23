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
    # Only allow DNS + traffic to inference pods (ollama or vllm) inside the namespace.
    # Fixed structure (was incorrectly creating two separate peers before).
    - to:
      - namespaceSelector:
          matchLabels:
            aegis/project: "true"
        podSelector:
          matchLabels:
            aegis/component: inference
      ports:
        - protocol: TCP
          port: {{ .InferencePort }}

    # Allow DNS (required for service discovery)
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53

    # TODO (Immediate gap): Add a second NetworkPolicy (or combine) that restricts
    # egress from `aegis/component: inference` pods themselves. Currently they have no restrictions.

---
apiVersion: v1
kind: NetworkPolicy
metadata:
  name: inference-deny-egress
  namespace: {{ .Namespace }}
spec:
  podSelector:
    matchLabels:
      aegis/component: inference
  policyTypes:
    - Egress
  egress:
    # Only allow DNS for now (can be tightened further)
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    # Allow traffic to Mission Control (if needed for future coordination)
    - to:
      - namespaceSelector:
          matchLabels:
            aegis/project: "true"
        podSelector:
          matchLabels:
            app: mission-control
      ports:
        - protocol: TCP
          port: 8080
