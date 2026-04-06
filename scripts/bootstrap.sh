#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[*] Creating namespaces (idempotent)..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -

echo "[*] Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
helm repo update >/dev/null

echo "[*] Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f "$ROOT/helm-values/prometheus-values.yaml"

echo "[*] Applying custom alert rules..."
kubectl apply -f "$ROOT/manifests/alerts/pod-restart-alert.yaml"

echo "[*] Installing Elasticsearch..."
helm upgrade --install elasticsearch bitnami/elasticsearch \
  -n logging \
  -f "$ROOT/helm-values/elasticsearch-values.yaml"

echo "[*] Installing Kibana..."
helm upgrade --install kibana bitnami/kibana \
  -n logging \
  -f "$ROOT/helm-values/kibana-values.yaml"

echo "[*] Installing Fluentd..."
helm upgrade --install fluentd bitnami/fluentd \
  -n logging \
  -f "$ROOT/helm-values/fluentd-values.yaml"

cat <<'MSG'

? Observability stack deployment kicked off.

Next:
1) Wait for pods to be Ready:
   kubectl -n monitoring get pods
   kubectl -n logging get pods
2) Open dashboards locally:
   ./scripts/port-forward.sh
3) Generate some load/logs to watch the dashboards light up.
MSG