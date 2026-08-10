#!/usr/bin/env bash
set -euo pipefail

context="${KUBE_CONTEXT:-kubernetes-admin@kubernetes}"

# Worker kubelet addresses are reachable from the node network, not from this
# cluster's pod overlay. Port 4443 avoids colliding with kubelet's host port
# 10250 when metrics-server uses host networking.
kubectl patch deployment metrics-server -n kube-system --context="$context" --type=strategic -p '
spec:
  template:
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
        - name: metrics-server
          args:
            - --cert-dir=/tmp
            - --secure-port=4443
            - --kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP
            - --kubelet-use-node-status-port
            - --metric-resolution=15s
            - --kubelet-insecure-tls
          ports:
            - name: https
              containerPort: 4443
              protocol: TCP
'

kubectl rollout status deployment/metrics-server -n kube-system \
  --context="$context" --timeout=180s
kubectl top nodes --context="$context"
