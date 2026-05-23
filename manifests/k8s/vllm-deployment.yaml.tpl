apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm
  namespace: {{ .Namespace }}
  labels:
    app: vllm
    aegis/component: inference
spec:
  replicas: {{ .InferenceReplicas }}
  selector:
    matchLabels:
      app: vllm
  template:
    metadata:
      labels:
        app: vllm
        aegis/component: inference
        nvidia.com/gpu: "true"
    spec:
      nodeSelector:
        {{ .GPUNodeSelectorKey }}: "{{ .GPUNodeSelectorValue }}"
      containers:
        - name: vllm
          image: {{ .InferenceImage }}
          imagePullPolicy: {{ .ImagePullPolicy }}
          command: ["python", "-m", "vllm.entrypoints.openai.api_server"]
          args:
            - "--model"
            - "/models/{{ .ModelLocalPath }}"
            - "--served-model-name"
            - "{{ .ModelName }}"
            - "--host"
            - "0.0.0.0"
            - "--port"
            - "{{ .InferencePort }}"
            - "--trust-remote-code"
            # T4 (16GB) friendly defaults — adjust per your model/quantization
            - "--gpu-memory-utilization"
            - "0.82"
            - "--max-model-len"
            - "2048"
            {{- if .ModelQuantization }}
            - "--quantization"
            - "{{ .ModelQuantization }}"
            {{- end }}
            - "--enforce-eager"   # More reliable on T4 / older CUDA for some models
            # Uncomment for even lower memory:
            # - "--load-in-8bit"
            # or use a pre-quantized AWQ/GPTQ model in the profile
          env:
            - name: NVIDIA_VISIBLE_DEVICES
              value: "all"
            - name: HF_HOME
              value: "/root/.cache/huggingface"
            - name: HF_HUB_OFFLINE
              value: "1"   # ensure no internet attempt in air-gap
            - name: VLLM_USE_MODEL_CACHE
              value: "1"
          ports:
            - containerPort: {{ .InferencePort }}
              name: api
          resources:
            limits:
              nvidia.com/gpu: {{ .GPUCount }}
            requests:
              cpu: "2"
              memory: "6Gi"   # vLLM + model weights in RAM need headroom on T4 nodes
          volumeMounts:
            - name: models
              mountPath: /models
            - name: hf-cache
              mountPath: /root/.cache/huggingface
          readinessProbe:
            httpGet:
              path: /health
              port: {{ .InferencePort }}
            initialDelaySeconds: 60
            periodSeconds: 15
            timeoutSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: {{ .InferencePort }}
            initialDelaySeconds: 120
            periodSeconds: 30
      volumes:
        - name: models
          hostPath:
            path: /opt/aegis/models
            type: DirectoryOrCreate
        - name: hf-cache
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: vllm
  namespace: {{ .Namespace }}
spec:
  selector:
    app: vllm
  ports:
    - port: {{ .InferencePort }}
      targetPort: {{ .InferencePort }}
      name: api
  type: ClusterIP
