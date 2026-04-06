#!/usr/bin/env bash
set -euo pipefail

echo "[*] Port-forwarding Grafana (3000), Prometheus (9090), Kibana (5601)..."
echo "Press Ctrl+C to stop."

kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 \
  >/tmp/grafana-port-forward.log 2>&1 &
GRAFANA_PID=$!

kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 \
  >/tmp/prometheus-port-forward.log 2>&1 &
PROM_PID=$!

kubectl -n logging port-forward svc/kibana 5601:5601 \
  >/tmp/kibana-port-forward.log 2>&1 &
KIBANA_PID=$!

trap 'echo "[*] Stopping port-forwards"; kill $GRAFANA_PID $PROM_PID $KIBANA_PID' INT TERM

wait