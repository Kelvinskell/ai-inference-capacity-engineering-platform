# Platform Architecture

## Context

This document describes the implemented architecture for a GPU-backed,
OpenAI-compatible AI inference platform on Amazon EKS. The platform combines
KServe and vLLM for model serving, Envoy AI Gateway for the public inference
path, S3-backed model delivery, KEDA for workload-driven scaling, and
Prometheus/Grafana for capacity engineering evidence.

Primary objectives:

- Serve the DeepSeek-R1-Distill-Qwen-14B-AWQ model on GPU capacity in EKS.
- Use gateway policies to control and account for model access before traffic
	reaches the predictor.
- Scale predictor replicas from measured queue, cache, and latency signals.
- Correlate inference behavior with GPU utilization and memory telemetry.
- Produce repeatable performance evidence for capacity and cost decisions.

## Diagram

![Platform architecture diagram](ai-inference-platform.png)

- **Mermaid source:** [platform-architecture-diagram.md](platform-architecture-diagram.md)

## High-Level System

The platform is composed of:

- AWS networking, EKS, S3, and cluster controllers provisioned through
	Terraform.
- Karpenter-managed GPU NodePools with a Spot-first, on-demand fallback policy.
- A KServe `RawDeployment` InferenceService running vLLM's OpenAI-compatible
	server for DeepSeek R1 14B AWQ.
- Envoy Gateway and Envoy AI Gateway for the internet-facing request path,
	OpenAI schema routing, authentication, rate limiting, and model quotas.
- Mountpoint for Amazon S3 CSI storage for shared, read-only model artifacts.
- kube-prometheus-stack, DCGM Exporter, Grafana, and Alertmanager for platform
	and serving observability.
- KEDA scaling driven by Prometheus queries over vLLM metrics.
- A benchmark harness and report that establish the initial per-replica
	performance envelope.

## Request Path

The production-intent inference path is:

1. A client sends an OpenAI-compatible request to the public Network Load
	 Balancer created for the EnvoyProxy LoadBalancer Service.
2. Envoy Gateway receives the request through the `envoy-ai-gateway` Gateway in
	 the `llm-serving` namespace.
3. The gateway applies its request controls and the `AIGatewayRoute` selects
	 the `deepseek-r1-14b` AI service backend using the OpenAI schema.
4. The backend resolves
	 `deepseek-r1-14b-predictor.llm-serving.svc.cluster.local:80`.
5. The KServe-generated predictor Service forwards to a vLLM container on port
	 `8000`.
6. vLLM reads the DeepSeek R1 14B AWQ artifacts mounted at `/models` and uses
	 one NVIDIA GPU per predictor pod.

Open WebUI is deployed as an optional in-cluster client. Its HTTP routes are
also attached to the Envoy Gateway, and it calls the same OpenAI-compatible
gateway API rather than a direct predictor endpoint.

## Component Breakdown

### 1. AWS Infrastructure and EKS Foundation

Terraform composes the development environment from networking, EKS, model
storage, GPU capacity, monitoring, KServe, Envoy AI Gateway, KEDA, and Open
WebUI modules.

Implemented foundation:

- A VPC with public and private subnet ranges and configurable NAT gateway
	mode.
- An EKS control plane placed in the private subnets supplied by the networking
	module, with endpoint access and authentication mode configured as
	environment inputs.
- EKS add-ons for Mountpoint for Amazon S3 CSI, Metrics Server, and the EKS Pod
	Identity Agent.
- A private S3 model bucket with versioning, AES-256 default encryption, and
	public-access blocking.
- A Pod Identity association that grants the `model-uploader` ServiceAccount
	access to the model-storage role.

This separates infrastructure ownership from workload configuration: Terraform
installs the platform dependencies, while Kubernetes manifests express the
service-specific behavior.

### 2. GPU Capacity and Scheduling

The predictor requests `nvidia.com/gpu: "1"`, selects nodes labelled
`gpu: "true"`, and tolerates the `nvidia.com/gpu=true:NoSchedule` taint.

Karpenter defines two GPU NodePools:

- `gpu-spot` has weight `100`, making it the preferred elastic capacity tier.
	It consolidates empty or underutilized nodes after five minutes.
- `gpu-on-demand` has weight `10` and provides the baseline capacity tier. It
	consolidates empty nodes after fifteen minutes.

Both pools use the `gpu` NodeClass, restrict scheduling to configured AMD64 GPU
instance types, and cap their aggregate GPU allocation through NodePool limits.
The separation allows cost-oriented Spot preference without making on-demand
capacity unavailable when Spot is constrained.

### 3. Model Storage and Delivery

Model artifacts are delivered independently of the serving image:

- The `s3-model-uploader` Job runs in `model-storage`, executes the committed
	Python synchronization script, and uploads validated artifacts to S3.
- The static `deepseek-r1-14b` persistent volume uses the S3 CSI driver with
	driver-level authentication and a `ReadOnlyMany` claim.
- The DeepSeek predictor mounts the
	`models/deepseek-14b-awq` prefix at `/models` as read-only.

This design avoids embedding large model weights in the vLLM image and gives
new predictor pods a consistent artifact source. It does not eliminate cold
start work: startup still includes FUSE-backed S3 reads, GPU weight loading,
vLLM initialization, and KV-cache allocation.

### 4. Serving, Gateway, and Access Controls

The serving control plane is KServe. The `deepseek-r1-14b` InferenceService
uses `RawDeployment` rather than serverless mode and declares
`serving.kserve.io/autoscalerClass: external`, leaving replica ownership to
KEDA. The predictor runs `vllm/vllm-openai:v0.25.1` with a 90% GPU memory target,
a 15,000-token model length, 40 maximum sequences, and 2,048 maximum batched
tokens.

Envoy Gateway exposes an internet-facing NLB with IP targets and a 480-second
TCP idle timeout. Envoy AI Gateway routes the model through an
`AIGatewayRoute`, `AIServiceBackend`, and `Backend` resource chain. The route
sets a 420-second request timeout.

The gateway manifests define:

- API-key authentication from the `Authorization` header, with the authenticated
	identity forwarded as `x-client-id`.
- A 420-second HTTP stream idle timeout and 50 MiB connection buffer limit.
- A local rate-limit rule of 100 requests per second.
- A per-model quota policy with a 100 million tokens/day default bucket and a
	one million tokens/day bucket for `development-client`.
- A Redis StatefulSet and headless Service in `redis-system`, used as the Envoy
	Gateway rate-limit backend.

The checked-in security and local rate-limit manifests target an `HTTPRoute`,
while the inference route is an `AIGatewayRoute`. The quota policy correctly
targets the `AIServiceBackend`. End-to-end gateway validation should therefore
confirm the intended authentication and local rate-limit attachment before this
is treated as a production enforcement guarantee.

### 5. Autoscaling and Capacity Signals

KEDA owns the `deepseek-r1-14b-predictor` replica count from one to six replicas.
It polls Prometheus every 15 seconds, waits 180 seconds before cooldown, and
uses controlled HPA behavior: scale-up can double replicas every 30 seconds
after a 60-second stabilization window, while scale-down removes up to 25% every
60 seconds after a five-minute stabilization window.

The three implemented scale triggers are:

- Queue depth: scale when the sum of `vllm:num_requests_waiting` reaches `2`.
- KV-cache demand: scale when the sum of `vllm:kv_cache_usage_perc` reaches
	`0.75`.
- Tail latency: scale when p99 `vllm:request_inference_time_seconds` reaches
	`30` seconds.

These values are derived from the committed benchmark evidence, not generic
defaults. Under the standard 1,024-input-token and 128-output-token workload,
one ready predictor reached a practical planning capacity of roughly 1.5
successful requests per second. At concurrency 40, throughput plateaued at
1.63 requests per second while p99 latency rose to 35.5 seconds and the queue
reached 25 waiting requests. Queueing first appeared at concurrency 5, which
supports scaling on queue pressure before the user-visible latency cliff.

### 6. Observability and Alerting

The monitoring module installs kube-prometheus-stack with Grafana and
persistent Prometheus storage. It also installs DCGM Exporter only on nodes
labelled `gpu: "true"`; the exporter tolerates the GPU taint so it can collect
GPU utilization and framebuffer metrics from inference nodes.

The `deepseek-r1-14b` ServiceMonitor scrapes the predictor's `/metrics` endpoint
every 15 seconds. Prometheus is therefore the shared metric source for:

- KEDA queue, KV-cache, and latency triggers.
- Grafana GPU, latency, and inference dashboards provisioned from ConfigMaps.
- Alertmanager and custom GPU recording and alert rules.
- The benchmark collector, which queries vLLM scheduler, token, DCGM GPU, and
	memory metrics for each measurement window.

### 7. Benchmark and Validation Layer

The benchmark suite drives non-streaming OpenAI-compatible requests through the
authenticated Envoy Gateway path, then records request-level results and the
matching Prometheus measurement window. It evaluates throughput, time to first
token, latency percentiles, scheduler queue pressure, KV-cache use, and GPU
behavior rather than treating a single request-rate value as sufficient
capacity evidence.

The report shows that output length and prompt length materially change the
capacity envelope. For example, at concurrency 20, increasing requested output
from 128 to 1,024 tokens reduced successful-request throughput from 1.54 to
0.45 requests per second and raised p99 latency from 15.8 to 48.8 seconds.
Capacity planning and admission controls must therefore account for token
budgets as well as request concurrency.

## Reference Paths

### Infrastructure and Platform Controllers

- [Terraform development environment](../../terraform/environments/dev/main.tf)
- [EKS module](../../terraform/modules/eks)
- [GPU NodePool definitions](../../terraform/modules/gpu-node/nodepool.tf)
- [Monitoring module](../../terraform/modules/monitoring)
- [Envoy Gateway and AI Gateway module](../../terraform/modules/envoy_ai_gateway)
- [KEDA module](../../terraform/modules/keda)
- [S3 model storage module](../../terraform/modules/s3-model-storage)

### Workload and Gateway Configuration

- [DeepSeek KServe deployment](../../kubernetes/serving/kserve/deepseek-r1-14b/deployment.yaml)
- [S3-backed persistent volume](../../kubernetes/serving/kserve/deepseek-r1-14b/persistent-volume.yaml)
- [vLLM ServiceMonitor](../../kubernetes/serving/kserve/deepseek-r1-14b/service-monitor.yaml)
- [Envoy Gateway](../../kubernetes/gateway/gateway.yaml)
- [AI Gateway route](../../kubernetes/gateway/route.yaml)
- [AI service backend](../../kubernetes/gateway/backend.yaml)
- [KEDA ScaledObject](../../kubernetes/autoscaling/scaledobject.yaml)

### Operations and Evidence

- [vLLM serving runbook](../runbooks/vllm-serving.md)
- [Benchmark runbook](../runbooks/benchmark-runbook.md)
- [Inference performance benchmark report](../reports/2026-08-17-inference-performance-benchmark-report.md)
- [Benchmark-derived autoscaling decision](../decisions/002-benchmark-derived-autoscaling-triggers.md)

## Architecture Decisions Captured

- KServe manages the inference workload, while KEDA is the single autoscaling
	owner for the predictor deployment.
- Envoy AI Gateway is the public inference entry point; direct predictor access
	is reserved for local troubleshooting.
- S3 is the durable model-artifact source, mounted read-only through the S3 CSI
	driver rather than baked into the runtime image.
- Spot GPU capacity is preferred, with on-demand GPU capacity retained as the
	baseline fallback.
- Prometheus is both the observability backend and the autoscaling signal
	source, so scaling decisions can be investigated against the same metrics used
	for operations and benchmarking.
- Predictor minimum replicas remain at one because model mounting, model loading,
	GPU allocation, and node provisioning make scale-from-zero unsuitable for the
	measured service profile.

## What This Architecture Optimizes For

- A reproducible and observable request path from client through gateway to GPU
	inference.
- Evidence-based scale-out before queue growth becomes severe tail latency.
- GPU capacity that can use lower-cost Spot instances while retaining a defined
	baseline tier.
- Reusable model artifacts without bloating serving images.
- Clear ownership boundaries between infrastructure provisioning, platform
	controllers, workload manifests, and benchmark evidence.

The KServe InferenceService uses `RawDeployment` mode and delegates replica management to KEDA. Each predictor pod runs vLLM's OpenAI server, exposes its metrics on port `8000`, and requests one NVIDIA GPU. Open WebUI is deployed as an optional in-cluster client and is also exposed through the same gateway.

## Access and Traffic Controls

Envoy Gateway provides the entry-point controls for the inference API. The configured resources provide API-key authentication, client identity forwarding, request and stream timeouts, local request rate limiting, and model token quotas. Redis runs in the `redis-system` namespace and provides the rate-limit backend state used by Envoy Gateway.

## Model Storage

The model uploader Job downloads and validates model artifacts before uploading them to the private, versioned, encrypted S3 model bucket. Predictor pods mount the required model prefix through the Mountpoint for Amazon S3 CSI driver using a `ReadOnlyMany` persistent volume claim. This separates model delivery from the pod image and lets replacement pods use the shared model source.

## Scaling and GPU Capacity

KEDA queries Prometheus for vLLM queue depth, KV-cache usage, and p99 inference latency. Its ScaledObject adjusts the predictor workload between one and six replicas. Karpenter provides GPU capacity with a preferred Spot NodePool and an on-demand baseline NodePool. Both pools are labelled for AI inference and tainted so only GPU-tolerant workloads schedule there.

## Observability

The kube-prometheus-stack collects vLLM metrics through a ServiceMonitor and GPU telemetry through DCGM Exporter on GPU nodes. Prometheus supplies the data used by KEDA, Grafana dashboards, and Alertmanager, allowing inference latency, request pressure, cache usage, and GPU utilization to be correlated.
