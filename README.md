# 🔭 k8s-observability-stack

A production-ready, end-to-end Kubernetes observability stack that brings together **metrics, logs, dashboards, and alerting** in a single bootstrapable setup. Deploy the full stack with one script and get Grafana dashboards, Prometheus alerting, and a centralized EFK log pipeline running in minutes.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [Helm Configuration](#helm-configuration)
  - [Prometheus Stack](#prometheus-stack)
  - [Elasticsearch](#elasticsearch)
  - [Kibana](#kibana)
  - [Fluentd](#fluentd)
- [Grafana Dashboards](#grafana-dashboards)
  - [Pod & Node Resource Overview](#pod--node-resource-overview)
  - [Pod Health & Restarts](#pod-health--restarts)
- [Alerting](#alerting)
- [Accessing the UIs](#accessing-the-uis)
- [Namespaces](#namespaces)
- [Troubleshooting](#troubleshooting)

---

## Overview

This repository provides an opinionated but minimal observability stack for Kubernetes using the industry-standard open-source toolchain:

| Concern | Tool |
|---|---|
| **Metrics collection** | Prometheus + Node Exporter + kube-state-metrics |
| **Metrics visualization** | Grafana |
| **Alerting** | Prometheus Alertmanager |
| **Log collection** | Fluentd (DaemonSet) |
| **Log storage** | Elasticsearch |
| **Log visualization** | Kibana |

Everything is deployed via **Helm** with custom `values.yaml` overrides and a single `bootstrap.sh` script that wires it all together idempotently.

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│                                                          │
│  namespace: monitoring            namespace: logging     │
│  ┌─────────────────────────┐     ┌────────────────────┐ │
│  │  kube-prometheus-stack  │     │  EFK Stack         │ │
│  │  ┌─────────────────┐    │     │  ┌──────────────┐  │ │
│  │  │  Prometheus     │    │     │  │ Elasticsearch│  │ │
│  │  │  (scrape/store) │    │     │  │ (store/index)│  │ │
│  │  └────────┬────────┘    │     │  └──────┬───────┘  │ │
│  │           │             │     │         │          │ │
│  │  ┌────────▼────────┐    │     │  ┌──────▼───────┐  │ │
│  │  │  Alertmanager   │    │     │  │   Kibana     │  │ │
│  │  │  (fire alerts)  │    │     │  │  (visualize) │  │ │
│  │  └─────────────────┘    │     │  └──────────────┘  │ │
│  │  ┌─────────────────┐    │     │  ┌──────────────┐  │ │
│  │  │    Grafana      │    │     │  │   Fluentd    │  │ │
│  │  │  (dashboards)   │    │     │  │ (collect logs│  │ │
│  │  └─────────────────┘    │     │  │  from nodes) │  │ │
│  │  ┌─────────────────┐    │     │  └──────────────┘  │ │
│  │  │  Node Exporter  │◄───┘     └────────────────────┘ │
│  │  │  kube-state-    │                                  │
│  │  │  metrics        │                                  │
│  │  └─────────────────┘                                  │
└──────────────────────────────────────────────────────────┘
```

**Data flow:**
- **Metrics**: Node Exporter & kube-state-metrics expose cluster metrics → Prometheus scrapes every 30s and retains data for 15 days → Grafana visualizes them.
- **Logs**: Fluentd runs as a DaemonSet, mounts host log paths (`/var/log`, `/var/lib/docker/containers`), and ships logs to Elasticsearch in Logstash format → Kibana provides search and visualization.
- **Alerts**: Prometheus evaluates `PrometheusRule` CRDs and fires alerts to Alertmanager.

---

## Components

### Monitoring Stack (`namespace: monitoring`)

| Component | Chart | Description |
|---|---|---|
| **Prometheus** | `prometheus-community/kube-prometheus-stack` | Scrapes metrics from the cluster every 30s, retains 15 days of data |
| **Alertmanager** | (bundled) | Receives and routes alerts fired by Prometheus rules |
| **Grafana** | (bundled) | Dashboard UI; auto-provisions custom dashboards via sidecar |
| **Node Exporter** | (bundled) | Per-node metrics — CPU, memory, disk, network |
| **kube-state-metrics** | (bundled) | Kubernetes object state metrics — pod phase, restart counts, etc. |

### Logging Stack (`namespace: logging`)

| Component | Chart | Description |
|---|---|---|
| **Elasticsearch** | `bitnami/elasticsearch` | Single-master search/store backend for logs |
| **Kibana** | `bitnami/kibana` | Log exploration and visualization UI |
| **Fluentd** | `bitnami/fluentd` | DaemonSet log forwarder; tails container and system logs from each node |

---

## Prerequisites

Before running the bootstrap script, ensure the following are installed and configured:

| Tool | Version | Purpose |
|---|---|---|
| `kubectl` | ≥ 1.24 | Kubernetes CLI |
| `helm` | ≥ 3.10 | Kubernetes package manager |
| A running Kubernetes cluster | — | Minikube, kind, K3s, EKS, GKE, AKS, etc. |

Verify access to your cluster:
```bash
kubectl cluster-info
kubectl get nodes
```

---

## Project Structure

```
k8s-observability-stack/
│
├── helm-values/                      # Helm value overrides for each chart
│   ├── prometheus-values.yaml        # kube-prometheus-stack config (Prometheus, Grafana, Alertmanager)
│   ├── elasticsearch-values.yaml     # Elasticsearch sizing & persistence
│   ├── kibana-values.yaml            # Kibana endpoint & resource limits
│   └── fluentd-values.yaml           # Fluentd log paths, ES target, resource limits
│
├── manifests/
│   └── alerts/
│       └── pod-restart-alert.yaml    # PrometheusRule CRD — high pod restart alert
│
├── dashboards/                       # Standalone Grafana dashboard JSON (reference copies)
│   ├── pod-node-resources.json       # Pod & Node Resource Overview dashboard
│   └── pod-health-restarts.json      # Pod Health & Restarts dashboard
│
└── scripts/
    ├── bootstrap.sh                  # One-shot deployment: namespaces → Helm installs → alert rules
    └── port-forward.sh               # Forwards Grafana :3000, Prometheus :9090, Kibana :5601 locally
```

> **Note:** The dashboard JSONs in `dashboards/` are reference copies. The authoritative copies are embedded inline inside `helm-values/prometheus-values.yaml` and are auto-provisioned into Grafana by the sidecar on deploy.

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/saiyash006/k8s-observability-stack.git
cd k8s-observability-stack
```

### 2. Make scripts executable

```bash
chmod +x scripts/bootstrap.sh scripts/port-forward.sh
```

### 3. Run the bootstrap

```bash
./scripts/bootstrap.sh
```

This single script will:
1. Create the `monitoring` and `logging` namespaces (idempotent — safe to re-run).
2. Add the `prometheus-community` and `bitnami` Helm repositories.
3. Install or upgrade **kube-prometheus-stack** with custom Grafana dashboards.
4. Apply the custom **PrometheusRule** alert manifest.
5. Install or upgrade **Elasticsearch**, **Kibana**, and **Fluentd**.

### 4. Wait for pods to become Ready

```bash
# Check monitoring namespace
kubectl -n monitoring get pods -w

# Check logging namespace
kubectl -n logging get pods -w
```

### 5. Open the dashboards

```bash
./scripts/port-forward.sh
```

Then open in your browser:

| UI | URL | Default Credentials |
|---|---|---|
| **Grafana** | http://localhost:3000 | `admin` / `prom-operator` |
| **Prometheus** | http://localhost:9090 | — |
| **Kibana** | http://localhost:5601 | — |

Press `Ctrl+C` to stop all port-forwards.

---

## Helm Configuration

### Prometheus Stack

**File:** [`helm-values/prometheus-values.yaml`](helm-values/prometheus-values.yaml)

Key settings:

| Setting | Value | Notes |
|---|---|---|
| `prometheus.prometheusSpec.scrapeInterval` | `30s` | How often Prometheus scrapes targets |
| `prometheus.prometheusSpec.retention` | `15d` | How long metrics are stored |
| `grafana.adminUser` | `admin` | Grafana login username |
| `grafana.adminPassword` | `prom-operator` | **Change before production use** |
| `grafana.defaultDashboardsEnabled` | `false` | Disables default Grafana dashboards; uses custom ones only |
| `nodeExporter.enabled` | `true` | Deploys Node Exporter as a DaemonSet on every node |
| `kubeStateMetrics.enabled` | `true` | Enables kube-state-metrics for pod/deployment/node state |
| `alertmanager.enabled` | `true` | Enables Alertmanager for routing fired alerts |

The Grafana sidecar (`grafana.sidecar.dashboards.enabled: true`) watches for ConfigMaps with the label `grafana_dashboard` and auto-provisions them — the two custom dashboards are embedded in this file as JSON under `grafana.dashboards.custom`.

---

### Elasticsearch

**File:** [`helm-values/elasticsearch-values.yaml`](helm-values/elasticsearch-values.yaml)

Runs a **single-master, no-persistence** configuration, suitable for development/staging:

| Role | Replicas | Notes |
|---|---|---|
| master | 1 | Handles cluster coordination |
| coordinating | 0 | Disabled |
| data | 0 | Data handled by master in this config |
| ingest | 0 | Disabled |
| persistence | disabled | Logs are ephemeral; enable for production |

Resource limits: `500m CPU`, `1Gi RAM`.

> ⚠️ **Production Note:** Enable `master.persistence.enabled: true` and add dedicated `data` nodes before using in production.

---

### Kibana

**File:** [`helm-values/kibana-values.yaml`](helm-values/kibana-values.yaml)

Connects to Elasticsearch at `http://elasticsearch.logging.svc.cluster.local:9200` (in-cluster DNS). Exposed as a `ClusterIP` service (accessed via port-forward locally).

Resource limits: `300m CPU`, `512Mi RAM`.

---

### Fluentd

**File:** [`helm-values/fluentd-values.yaml`](helm-values/fluentd-values.yaml)

Runs as a single replica that mounts three host paths to collect all container and system logs:

| Host Path | Purpose |
|---|---|
| `/var/log` | System-level logs |
| `/var/lib/docker/containers` | Raw Docker container logs |
| `/var/log/containers` | Symlinked container logs (Kubernetes standard) |

Logs are forwarded to Elasticsearch in **Logstash format** (`logstash_format: true`), creating daily indices (e.g., `logstash-2026.04.23`).

A `toleration` of `operator: Exists` ensures Fluentd runs on **all nodes**, including control-plane/master nodes that have taints.

Resource limits: `300m CPU`, `400Mi RAM`.

---

## Grafana Dashboards

Two custom dashboards are auto-provisioned into the **"Observability"** folder in Grafana. Both use Prometheus as the datasource and support namespace/pod variable templating.

### Pod & Node Resource Overview

**UID:** `pod-node-resources` | **File:** [`dashboards/pod-node-resources.json`](dashboards/pod-node-resources.json)

Provides a bird's-eye view of cluster resource consumption.

| Panel | Type | PromQL |
|---|---|---|
| **Node CPU %** | Stat | `100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| **Node Memory Used (GB)** | Stat | `(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024^3` |
| **Pod CPU (cores)** | Time series | `sum by(pod) (rate(container_cpu_usage_seconds_total{...}[5m]))` |
| **Pod Memory (MiB)** | Time series | `sum by(pod) (container_memory_working_set_bytes{...}) / 1024^2` |
| **Node Filesystem Usage %** | Time series | `(1 - node_filesystem_free_bytes / node_filesystem_size_bytes) * 100` |

**Template variables:** `$namespace`, `$pod` — filter all pod-level panels to a specific workload.

---

### Pod Health & Restarts

**UID:** `pod-health-restarts` | **File:** [`dashboards/pod-health-restarts.json`](dashboards/pod-health-restarts.json)

Focuses on pod stability and crash-loop detection.

| Panel | Type | PromQL |
|---|---|---|
| **Container Restarts (15m rate)** | Time series | `sum by(pod, container) (rate(kube_pod_container_status_restarts_total{namespace='$namespace'}[15m]))` |
| **Not Ready Pods** | Stat | `count(kube_pod_status_ready{namespace='$namespace', condition='false'})` |
| **Pod Phase Counts** | Time series | `sum by(phase) (kube_pod_status_phase{namespace='$namespace'})` |

**Template variable:** `$namespace` — drill into any namespace to watch its pod health.

---

## Alerting

### HighPodRestarts

**File:** [`manifests/alerts/pod-restart-alert.yaml`](manifests/alerts/pod-restart-alert.yaml)

A `PrometheusRule` CRD that fires a `warning`-severity alert when a pod restarts more than 3 times within a 15-minute window.

```yaml
alert: HighPodRestarts
expr: sum by(pod, namespace) (increase(kube_pod_container_status_restarts_total[15m])) > 3
for: 5m
severity: warning
```

| Field | Value | Meaning |
|---|---|---|
| `expr` | `increase(...[15m]) > 3` | Watches for ≥ 4 restarts in any 15-minute window |
| `for` | `5m` | Alert must be continuously true for 5 minutes before firing (reduces flapping) |
| `severity` | `warning` | Routes to the `warning` receiver in Alertmanager |

**Alert message:**
> *"Pod `<namespace>/<pod>` is restarting frequently — container restarts exceeded 3 in the last 15m. Check recent deployments or crash loops."*

To add more alert rules, create additional YAML files in `manifests/alerts/` following the same `PrometheusRule` CRD schema and apply them with `kubectl apply -f`.

---

## Accessing the UIs

All services are deployed as `ClusterIP` (not exposed externally). Use the provided port-forward script for local access:

```bash
./scripts/port-forward.sh
```

This runs three background port-forwards and blocks until you press `Ctrl+C`:

| Service | Local Port | Kubernetes Service |
|---|---|---|
| Grafana | `3000` | `svc/kube-prometheus-stack-grafana` in `monitoring` |
| Prometheus | `9090` | `svc/kube-prometheus-stack-prometheus` in `monitoring` |
| Kibana | `5601` | `svc/kibana` in `logging` |

Port-forward logs are written to `/tmp/grafana-port-forward.log`, `/tmp/prometheus-port-forward.log`, and `/tmp/kibana-port-forward.log`.

---

## Namespaces

| Namespace | Contents |
|---|---|
| `monitoring` | Prometheus, Grafana, Alertmanager, Node Exporter, kube-state-metrics |
| `logging` | Elasticsearch, Kibana, Fluentd |

Both namespaces are created idempotently by `bootstrap.sh` using `--dry-run=client` piped to `kubectl apply`, so re-running the script is always safe.

---

## Troubleshooting

**Pods not starting / OOMKilled?**
```bash
kubectl -n monitoring describe pod <pod-name>
kubectl -n logging describe pod <pod-name>
```
Elasticsearch requires at least `512Mi` memory. Increase node resources or adjust `elasticsearch-values.yaml` limits.

**Grafana dashboards not appearing?**
The Grafana sidecar scrapes configurations at startup. Check the sidecar container logs:
```bash
kubectl -n monitoring logs deployment/kube-prometheus-stack-grafana -c grafana-sc-dashboard
```

**Fluentd not shipping logs?**
Verify Elasticsearch is reachable from within the cluster:
```bash
kubectl -n logging exec -it deployment/fluentd -- curl -s http://elasticsearch.logging.svc.cluster.local:9200/_cluster/health
```

**Alert not appearing in Alertmanager?**
Confirm the `PrometheusRule` was picked up:
```bash
kubectl -n monitoring get prometheusrule
```
The rule must have the label `release: kube-prometheus-stack` to be discovered by the Prometheus operator.

**Re-deploying / upgrading?**
The bootstrap script uses `helm upgrade --install`, making it fully idempotent. Simply re-run:
```bash
./scripts/bootstrap.sh
```
