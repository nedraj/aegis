apiVersion: apps/v1
kind: Deployment
metadata:
  name: zot-registry
  namespace: {{ .Namespace }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zot
  template:
    metadata:
      labels:
        app: zot
    spec:
      containers:
        - name: zot
          image: {{ .ZotImage }}
          imagePullPolicy: {{ .ImagePullPolicy }}
          ports:
            - containerPort: 5000
          volumeMounts:
            - name: data
              mountPath: /var/lib/registry
      volumes:
        - name: data
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: zot-registry
  namespace: {{ .Namespace }}
spec:
  selector:
    app: zot
  ports:
    - port: 5000
      targetPort: 5000
  type: ClusterIP
