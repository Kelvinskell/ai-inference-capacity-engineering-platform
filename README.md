# AI Inference Capacity Engineering

**A production-grade, capacity-driven AI inference platform on Amazon EKS, built for high-throughput LLM serving, GPU efficiency, benchmark-derived autoscaling, and full-stack observability with KServe, vLLM, Envoy AI Gateway, KEDA, Prometheus, and Grafana.**

[![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?logo=amazonwebservices&logoColor=white)](https://aws.amazon.com/eks/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.36-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D%201.15-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![vLLM](https://img.shields.io/badge/vLLM-0.25.1-1F6FEB)](https://docs.vllm.ai/)
[![License](https://img.shields.io/badge/License-MIT-2EA44F)](LICENSE)

![AI inference platform architecture](docs/architecture/ai-inference-platform.png)

**Mermaid source:** [docs/architecture/platform-architecture-diagram.md](docs/architecture/platform-architecture-diagram.md)

## What This Project Proves

This repository is more than a collection of deployment manifests. It connects infrastructure, serving, traffic control, observability, benchmarking, and autoscaling into one capacity-engineering loop:

1. **Provision** an EKS platform with Terraform, EKS Auto Mode, S3 model storage, and Spot-first GPU capacity.
2. **Serve** a pinned DeepSeek-R1-Distill-Qwen-14B-AWQ revision with KServe `RawDeployment` and vLLM.
3. **Protect** the OpenAI-compatible API with authentication, request limits, token quotas, and inference-aware timeouts.
4. **Measure** request latency, token throughput, scheduler pressure, KV-cache demand, and NVIDIA GPU telemetry.
5. **Scale** from benchmark-derived Prometheus signals instead of generic CPU utilization.

The result is a reproducible platform for answering the questions that matter in inference operations: *Where is the throughput ceiling? When does queueing begin? What does a safe per-replica capacity target look like? Which signal should initiate scale-out before users see a latency cliff?*

## Measured Capacity Envelope

The committed benchmark report establishes an initial envelope for **one ready GPU-backed predictor**, using non-streaming requests with 1,024 input tokens and 128 output tokens through the complete authenticated Envoy path.

| Concurrency | Successful requests/s | Total tokens/s | p95 latency | p99 latency | Avg waiting requests | Max waiting requests |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0.33 | 381 | 3.1s | 3.1s | 0.000 | 0 |
| 5 | 0.98 | 1,134 | 5.1s | 5.2s | 0.242 | 2 |
| 10 | 1.32 | 1,518 | 8.0s | 8.5s | 1.152 | 5 |
| 20 | 1.54 | 1,778 | 13.9s | 15.5s | 1.424 | 7 |
| 40 | 1.63 | 1,879 | 25.9s | 35.5s | 2.000 | 25 |

### What The Data Says

- **Practical planning capacity:** approximately **1.5 successful requests/s per replica** for the tested 1,024/128-token workload.
- **Saturation behavior:** doubling concurrency from 20 to 40 adds only 0.09 requests/s while p99 latency more than doubles.
- **Queue behavior:** brief queueing first appears at concurrency 5, while average queue depth rises from 0.242 at concurrency 5 to 2.000 at concurrency 40.
- **Sustained pressure:** average queue depth reaches 2 only at the saturation point, where p99 latency is already 35.5s; maximum queue depth captures bursts but does not drive the KEDA trigger.
- **GPU behavior:** utilization remains at 100%; memory stays near 86-87%; no vLLM preemptions are recorded.
- **Request shape matters:** at concurrency 20, increasing output length from 128 to 1,024 tokens drops throughput from 1.54 to 0.45 requests/s and raises p99 latency from 15.8s to 48.8s.

These results inform three independent KEDA signals: a rolling one-minute average queue depth of 2, 75% KV-cache utilization, and 30s p99 inference latency. The queue threshold is an initial saturation guardrail that must be validated during multi-replica scale tests; it is not an early-queue threshold derived from the maximum value. See the [full benchmark report](docs/reports/2026-08-17-inference-performance-benchmark-report.md) and [autoscaling decision record](docs/decisions/002-benchmark-derived-autoscaling-triggers.md).

> [!NOTE]
> This is an initial capacity envelope, not a universal model or GPU claim. It covers one model revision, one ready predictor, the tested vLLM configuration, and non-streaming requests. Prompt length, output length, GPU type, caching behavior, and scheduler settings all change the result.

## Architecture

```text
API client / Open WebUI
					|
					v
Internet-facing AWS NLB
					|
					v
Envoy Gateway + Envoy AI Gateway
	| authentication | rate limit | token quota | timeout
					|
					v
KServe InferenceService (RawDeployment)
					|
					v
vLLM OpenAI server: DeepSeek R1 14B AWQ
	| S3-mounted model | 1 NVIDIA GPU per replica | /metrics
					|
					+------------------------------+
																				 |
Prometheus <--- vLLM + DCGM Exporter ----+
		|                    |
		v                    v
KEDA autoscaling    Grafana + Alertmanager
		|
		v
Karpenter Spot-first / On-Demand GPU NodePools
```

The detailed [platform architecture](docs/architecture/platform-architecture.md) explains every component and ownership boundary. The editable diagram source is in [docs/architecture/platform-architecture-diagram.md](docs/architecture/platform-architecture-diagram.md).

### Platform Layers

| Layer | Implementation | Engineering purpose |
|---|---|---|
| Cloud foundation | VPC, public/private subnets, EKS, IAM, Pod Identity | Isolated, repeatable AWS infrastructure |
| GPU capacity | Karpenter `gpu-spot` and `gpu-on-demand` NodePools | Prefer elastic Spot capacity with an on-demand fallback |
| Model storage | Versioned, encrypted S3 + Mountpoint CSI | Decouple large model artifacts from serving images |
| Serving | KServe `RawDeployment` + vLLM | Explicit replica ownership and OpenAI-compatible inference |
| Gateway | Envoy Gateway + Envoy AI Gateway | Model-aware routing and policy enforcement at ingress |
| Autoscaling | KEDA + Prometheus queries | Scale on queue, KV-cache, and tail-latency pressure |
| Observability | kube-prometheus-stack, DCGM, Grafana, Alertmanager | Correlate user latency, scheduler state, and GPU behavior |
| Evidence | Async load generator + exact-window metric collection | Turn benchmark runs into capacity recommendations |

## Design Highlights

### Spot-First GPU Scheduling

Karpenter manages two tainted GPU pools. `gpu-spot` has weight 100 and consolidates underutilized capacity after five minutes; `gpu-on-demand` has weight 10 and retains baseline capacity longer. Predictor pods request one NVIDIA GPU and can schedule on either tier. The dev defaults allow up to two on-demand and four Spot GPUs.

### Verified Model Artifacts

The model uploader downloads exact Hugging Face revisions, calculates SHA-256 hashes, skips unchanged S3 objects, and writes `_MANIFEST.json` only after every upload succeeds. The serving pod mounts the validated `models/deepseek-14b-awq` prefix read-only through the S3 CSI driver. See [ADR 003](docs/decisions/003-s3-model-artifact-storage.md) and the [uploader implementation](scripts/s3-model-upload/sync_models_to_s3.py).

### Inference-Aware Gateway Controls

The public API uses an AWS Network Load Balancer and Envoy's Gateway API implementation. The configured path includes API-key authentication, client identity propagation, a 100 requests/s local limit, per-model token quotas backed by Redis, a 420s inference timeout, and a 480s NLB idle timeout. The rationale and trust boundaries are documented in [ADR 001](docs/decisions/001-envoy-ai-gateway-architecture.md).

### One Autoscaling Owner

KServe creates the predictor deployment, but KEDA alone owns its replica count. The service scales from 1 to 6 replicas, polls Prometheus every 15 seconds, doubles cautiously during pressure, and scales down only after a five-minute stabilization window. This avoids competing reconcilers and keeps one warm replica for a model whose mount, load, and GPU-node startup costs make scale-to-zero unsuitable.

## Repository Map

```text
.
├── .github/workflows/                 # OIDC-based Terraform and Kubernetes delivery
├── benchmarks/inference-performance/
│   ├── configs/profiles/              # Hypothesis-driven benchmark profiles
│   ├── corpus/                        # Deterministic prompt source
│   ├── python/                        # Load generation, statistics, metrics
│   └── run-benchmark.sh               # Benchmark orchestrator
├── docs/
│   ├── architecture/                  # System narrative and diagram source
│   ├── decisions/                     # Architecture decision records
│   ├── reports/                       # Measured benchmark conclusions
│   └── runbooks/                      # Deployment and troubleshooting procedures
├── kubernetes/
│   ├── autoscaling/                   # Benchmark-derived KEDA ScaledObject
│   ├── gateway/                       # Envoy routes, policy, quota, and Redis
│   ├── observability/                 # GPU recording and alert rules
│   ├── open-webui/                    # Cross-namespace UI route
│   ├── serving/kserve/                # DeepSeek vLLM InferenceService
│   └── storage/                       # Model uploader workload
├── scripts/s3-model-upload/           # Pinned, hash-verified model synchronization
└── terraform/
		├── environments/dev/              # Deployable development composition
		└── modules/                       # Network, EKS, GPU, serving, and platform modules
```

## Quick Start

### Prerequisites

- An AWS account with permissions for EKS, EC2/VPC, IAM, S3, and load balancing
- Terraform `>= 1.15.0`, AWS CLI, `kubectl`, `jq`, `curl`, and Python 3
- An S3 backend bucket for Terraform state
- Access to supported NVIDIA GPU instances in the selected region
- For CI/CD: GitHub Actions OIDC trust and a deployment role exposed as `ROLE_ARN`

### 1. Configure The Dev Environment

```bash
cp terraform/environments/dev/terraform.tfvars.example \
	terraform/environments/dev/terraform.tfvars

# Edit account, IAM principal, network, region, and cluster values.
cd terraform/environments/dev
terraform init -reconfigure
terraform fmt -check -recursive
terraform validate
terraform plan
```

The example is intentionally free of real account details. Review the complete input surface in [terraform/environments/dev/variables.tf](terraform/environments/dev/variables.tf) and module composition in [terraform/environments/dev/main.tf](terraform/environments/dev/main.tf).

### 2. Provision The Platform

```bash
terraform apply
aws eks update-kubeconfig \
	--name ai-inference-eks-dev \
	--region eu-west-1
```

Terraform provisions the cloud foundation and installs the platform controllers: kube-prometheus-stack, DCGM Exporter, KServe, Knative, Istio, Envoy AI Gateway, KEDA, and Open WebUI.

### 3. Deploy Workloads

The preferred path is the [Kubernetes GitHub Actions workflow](.github/workflows/kubernetes-pipeline.yml), which creates the uploader ConfigMap, synchronizes model artifacts, waits for the upload Job, and applies workloads in dependency order.

For a local deployment, reproduce that sequence from the repository root:

```bash
kubectl apply -f kubernetes/namespaces

kubectl create configmap model-uploader-script \
	--namespace model-storage \
	--from-file=sync_models_to_s3.py=scripts/s3-model-upload/sync_models_to_s3.py \
	--from-file=requirements.txt=scripts/s3-model-upload/requirements.txt \
	--dry-run=client -o yaml | kubectl apply -f -

kubectl delete job s3-model-uploader -n model-storage --ignore-not-found
kubectl apply -f kubernetes/storage
kubectl apply -f kubernetes/observability
kubectl wait -n model-storage --for=condition=complete \
	job/s3-model-uploader --timeout=20m

kubectl apply -f kubernetes/serving/kserve/deepseek-r1-14b
kubectl apply -f kubernetes/gateway
kubectl apply -f kubernetes/autoscaling
kubectl apply -f kubernetes/open-webui
```

## Validate The Platform

### Control Plane And Workloads

```bash
kubectl get nodes -L gpu,capacity-tier
kubectl get pods -A
kubectl -n llm-serving get inferenceservice deepseek-r1-14b
kubectl -n llm-serving get gateway,aigatewayroute,aiservicebackend,backend
kubectl -n llm-serving get scaledobject,hpa
kubectl -n monitoring get servicemonitor,prometheusrule
```

The InferenceService should report `READY=True`, the Gateway should be programmed, and the predictor should expose a healthy metrics target before load testing.

### OpenAI-Compatible Inference

```bash
export GATEWAY_HOST="$(kubectl -n llm-serving get gateway envoy-ai-gateway \
	-o jsonpath='{.status.addresses[0].value}')"

# Authentication boundary: expected HTTP 401.
curl -i "http://${GATEWAY_HOST}/v1/models"

# Development smoke test: expected HTTP 200.
curl -sS "http://${GATEWAY_HOST}/v1/chat/completions" \
	-H "Authorization: Bearer notforprod" \
	-H "Content-Type: application/json" \
	-d '{
		"model": "/models",
		"messages": [{"role": "user", "content": "Explain GPU saturation in two sentences."}],
		"max_tokens": 64,
		"temperature": 0.2
	}' | jq .
```

The checked-in key is deliberately a **development-only credential**. Replace it before exposing the gateway beyond a controlled dev environment.

## Benchmarking

The harness maintains true asynchronous concurrency, generates exact-length prompts from a deterministic corpus, forces requested output lengths, records one JSON object per request, and queries Prometheus over the exact measurement window.

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install \
	-r benchmarks/inference-performance/python/requirements.txt

# Inspect expanded cases without sending traffic.
bash benchmarks/inference-performance/run-benchmark.sh plan

# Reproduce the principal saturation experiment.
bash benchmarks/inference-performance/run-benchmark.sh concurrency-saturation

# Run all active profiles. Allow approximately three hours.
caffeinate -dimsu \
	bash benchmarks/inference-performance/run-benchmark.sh all
```

Active profiles cover concurrency saturation, prompt length, output length, and scheduler batching. Generated CSV, request-level JSONL, logs, and tokenizer artifacts live under `benchmarks/inference-performance/results/` and are intentionally ignored by Git. Start with the [benchmark runbook](docs/runbooks/benchmark-runbook.md) for prerequisites, environment overrides, failure behavior, and result interpretation.

## Observability And Operations

Prometheus is the shared source for dashboards, alerts, autoscaling, and benchmark analysis. The platform collects:

- vLLM request, token, queue, scheduler, preemption, and KV-cache metrics
- DCGM GPU utilization, framebuffer memory, power, temperature, and activity metrics
- request-level latency, time to first token, time per output token, and success/error data
- derived five-minute GPU recording rules and alerts for sustained utilization, memory pressure, and missing DCGM targets

Grafana dashboards are provisioned from [terraform/modules/monitoring/grafana](terraform/modules/monitoring/grafana). Operational procedures are documented in:

- [vLLM serving runbook](docs/runbooks/vllm-serving.md)
- [Envoy AI Gateway runbook](docs/runbooks/envoy-gateway.md)
- [Benchmark runbook](docs/runbooks/benchmark-runbook.md)
- [DCGM metrics reference](docs/runbooks/dcgm-prometheus-metrics-reference.md)
- [DCGM missing-metrics troubleshooting](docs/runbooks/dcgm-metrics-missing.md)
- [vLLM Prometheus metrics reference](docs/runbooks/vllm-prometheus-metrics-refrence.md)

## Delivery Model

Two GitHub Actions workflows separate infrastructure from cluster workloads:

- [Terraform pipeline](.github/workflows/terraform-pipeline.yml): formats, validates, plans, and applies/destroys the dev environment using AWS OIDC.
- [Kubernetes pipeline](.github/workflows/kubernetes-pipeline.yml): configures cluster access, uploads models, then deploys observability, serving, gateway, autoscaling, and UI resources in order.

Environment variables hold account-specific configuration, while repository secrets are avoided through short-lived AWS credentials. The Terraform state backend remains encrypted in S3.

## Architecture Decisions

| Decision | Why it matters |
|---|---|
| [Envoy AI Gateway architecture](docs/decisions/001-envoy-ai-gateway-architecture.md) | Defines the public request path, identity boundary, quotas, and timeouts |
| [Benchmark-derived autoscaling](docs/decisions/002-benchmark-derived-autoscaling-triggers.md) | Connects observed queue and latency behavior to concrete scaling policy |
| [S3 model artifact storage](docs/decisions/003-s3-model-artifact-storage.md) | Defines reproducible model delivery, integrity checks, and shared mounting |

## Current Boundaries

This repository is deliberately honest about what has and has not been validated:

- The deployed application key and default Grafana/Open WebUI secrets are dev-only values and must be externalized and rotated for production.
- Redis and the Envoy rate-limit service run as single replicas; the current quota path is not highly available.
- Gateway policy attachment must be confirmed end to end before treating authentication and local rate limiting as a production enforcement guarantee.
- The benchmark covers one DeepSeek model revision, one ready predictor, one tested GPU path, and non-streaming completions.
- The 4,096-token prompt at concurrency 1 failed and must be rerun before drawing a conclusion from that case.
- KEDA thresholds are implemented, but full scale-event recovery still needs validation across pod startup, S3 mount, model load, and GPU-node provisioning.
- Disabled streaming, GPU-memory, and model-length profiles remain the next experiments.

## Teardown

Delete policy-bearing resources before destroying the infrastructure they reference:

```bash
kubectl delete -f kubernetes/autoscaling --ignore-not-found
kubectl delete -f kubernetes/gateway --ignore-not-found

cd terraform/environments/dev
terraform destroy
```

The Terraform workflow exposes the same destroy path for CI-driven cleanup.

## License

Licensed under the [MIT License](LICENSE).

## Connect

[Kelvin Onuchukwu on LinkedIn](https://www.linkedin.com/in/kelvin-onuchukwu-3460871a1/)