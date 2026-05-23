apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: {{ .Namespace }}
  labels:
    app: ollama
    aegis/component: inference
spec:
  replicas: {{ .OllamaReplicas }}
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
        aegis/component: inference
        nvidia.com/gpu: "true"
    spec:
      nodeSelector:
        {{ .GPUNodeSelectorKey }}: "{{ .GPUNodeSelectorValue }}"
      containers:
        - name: ollama
          image: {{ .OllamaImage }}
          imagePullPolicy: {{ .ImagePullPolicy }}
          ports:
            - containerPort: {{ .InferencePort }}
              name: api
          env:
            - name: OLLAMA_HOST
              value: "0.0.0.0:11434"
            - name: OLLAMA_MODELS
              value: "/root/.ollama/models"
            - name: NVIDIA_VISIBLE_DEVICES
              value: "all"
          resources:
            limits:
              nvidia.com/gpu: {{ .GPUCount }}
            requests:
              cpu: "500m"
              memory: "2Gi"
          volumeMounts:
            - name: models
              mountPath: /root/.ollama/models
            - name: cache
              mountPath: /root/.ollama/.cache
          readinessProbe:
            httpGet:
              path: /
              port: {{ .InferencePort }}
            initialDelaySeconds: 30
            periodSeconds: 10
      volumes:
        - name: models
          hostPath:
            path: /opt/aegis/models
            type: DirectoryOrCreate
        - name: cache
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: {{ .Namespace }}
spec:
  selector:
    app: ollama
  ports:
    - port: {{ .InferencePort }}
      targetPort: {{ .InferencePort }}
      name: api
  type: ClusterIP
