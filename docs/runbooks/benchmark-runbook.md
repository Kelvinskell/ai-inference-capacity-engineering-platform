# Runbook: Inference Performance Benchmark Suite

## Purpose

This runbook describes how to run the profile-driven inference benchmark suite for the `deepseek-r1-14b` KServe InferenceService. The service runs the AWQ-quantized DeepSeek-R1-Distill-Qwen-14B model through vLLM and receives benchmark traffic through Envoy AI Gateway.

The suite measures how request shape, concurrency, vLLM scheduling, GPU memory allocation, model context length, and streaming affect latency, throughput, queueing, KV-cache use, and GPU utilization.

The benchmark components are:

- [benchmarks/inference-performance/run-benchmark.sh](../../benchmarks/inference-performance/run-benchmark.sh): profile orchestration, KServe configuration, endpoint management, and result assembly.
- [benchmarks/inference-performance/python/loadgen.py](../../benchmarks/inference-performance/python/loadgen.py): asynchronous request generation and request-level measurements.
- [benchmarks/inference-performance/python/statistic.py](../../benchmarks/inference-performance/python/statistic.py): client-side statistics calculated from request-level output.
- [benchmarks/inference-performance/python/metrics.py](../../benchmarks/inference-performance/python/metrics.py): exact-window Prometheus queries for vLLM and DCGM metrics.
- [benchmarks/inference-performance/configs/profiles](../../benchmarks/inference-performance/configs/profiles): named experiment profiles and their hypotheses.
- [benchmarks/inference-performance/corpus/capacity-engineering.txt](../../benchmarks/inference-performance/corpus/capacity-engineering.txt): source corpus used to construct deterministic prompts.

## Request Path

The default local benchmark path is:

```text
loadgen.py
  -> http://127.0.0.1:18080/v1/completions
  -> Envoy data-plane Service
  -> AIGatewayRoute/deepseek-r1-14b
  -> Backend/deepseek-r1-14b
  -> deepseek-r1-14b-predictor.llm-serving.svc.cluster.local:80
  -> vLLM container on port 8000
```

Every inference request includes `Authorization: Bearer <INFER_API_KEY>`. This means benchmark results include Envoy authentication, routing, rate limiting, and transport overhead. The direct predictor Service is not used for benchmark traffic.

Prometheus and DCGM measurements remain scoped to the predictor pod and its GPU node. Envoy-specific latency and response-code metrics are not currently written to the benchmark CSV.

## Current Deployment Defaults

| Setting | Default |
|---|---|
| Kubernetes namespace | `llm-serving` |
| InferenceService | `deepseek-r1-14b` |
| Predictor Service | `deepseek-r1-14b-predictor` |
| Model artifact | `casperhansen/deepseek-r1-distill-qwen-14b-awq` |
| Model/tokenizer revision | `bc43ec1bbf08de53452630806d5989208b4186db` |
| vLLM model path and API model ID | `/models` |
| Inference URL | `http://127.0.0.1:18080/v1/completions` |
| Development API key | `notforprod` |
| Prometheus URL | `http://127.0.0.1:9090` |
| Warmup per case | 120 seconds |
| Measurement per case | 480 seconds |
| Load-generator request timeout | 380 seconds |
| Envoy request timeout | 420 seconds |
| Envoy HTTP stream-idle timeout | 420 seconds |
| AWS NLB TCP idle timeout | 480 seconds |

The checked-in API key is for development validation only. Set `INFER_API_KEY` to the active credential if the Secret has been changed.

```bash
export INFER_API_KEY="notforprod"
```

## Preconditions

Before starting a live benchmark, confirm:

1. The EKS cluster is reachable through the current `kubectl` context.
2. `deepseek-r1-14b` exists in `llm-serving`.
3. Envoy Gateway, Envoy AI Gateway, and their route resources are deployed.
4. The Prometheus stack and DCGM exporter are healthy.
5. The model storage is available to the predictor.
6. The local machine can remain awake and connected for the run.
7. `kubectl`, `jq`, `curl`, and `python3` are installed.
8. The benchmark Python dependencies are installed.

Install the Python dependencies in a virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r benchmarks/inference-performance/python/requirements.txt
```

The `transformers` dependency loads the pinned Hugging Face tokenizer. Ensure the tokenizer is already cached or that the machine can reach Hugging Face before beginning a long run.

## Cluster Validation

Run these checks when the cluster is online:

```bash
kubectl config current-context
kubectl -n llm-serving get inferenceservice deepseek-r1-14b
kubectl -n llm-serving get pods -o wide
kubectl -n llm-serving get gateway envoy-ai-gateway
kubectl -n llm-serving get aigatewayroute deepseek-r1-14b
kubectl -n monitoring get svc kube-prometheus-stack-prometheus
```

The InferenceService must report `Ready=True` before a benchmark case can begin.

## Automatic Port-Forwarding

The runner manages both local port-forwards. They do not need to be started manually.

### Envoy

When the local inference health endpoint is unavailable, the runner:

1. Searches `envoy-gateway-system` for exactly one Service whose name starts with `envoy-llm-serving-envoy-ai-gateway-`.
2. Starts a port-forward from local port `18080` to that Service's port `80`.
3. Checks `/health` with the configured bearer token.
4. Recreates the forward if it becomes unavailable during the run.

Set `ENVOY_SERVICE` explicitly if discovery returns zero or multiple matches.

### Prometheus

When `http://127.0.0.1:9090/-/ready` is unavailable, the runner starts:

```bash
kubectl -n monitoring port-forward \
  svc/kube-prometheus-stack-prometheus 9090:9090
```

Prometheus readiness is checked at startup and again before each metrics query. The runner recreates the forward if it drops. Port-forwards started by the runner are stopped when the runner exits.

Automatic forwarding is skipped when the configured URL is not local or when its corresponding `AUTO_PORT_FORWARD_*` setting is `false`.

## Benchmark Matrix

The allowed search space is defined in [benchmarks/inference-performance/configs/benchmark-matrix.sh](../../benchmarks/inference-performance/configs/benchmark-matrix.sh):

| Dimension | Allowed values |
|---|---|
| Prompt tokens | `128 1024 4096 8192 15000 30000 39872` |
| Requested output tokens | `128 512 1024` |
| Concurrency | `1 5 10 20 40 50 100` |
| GPU memory utilization | `0.80 0.85 0.90 0.95` |
| Maximum model length | `8192 15000 30000 40000` |
| Streaming | `false true` |

The 39,872-token prompt is paired with 128 output tokens to fill a 40,000-token context exactly. Profile validation rejects any prompt/output combination that exceeds the selected maximum model length.

## Profiles

| Profile | Cases | Primary variable |
|---|---:|---|
| `concurrency-saturation` | 7 | Concurrency from 1 through 100 |
| `prompt-length-scaling` | 49 | Seven prompt lengths across seven concurrency levels |
| `output-length-scaling` | 21 | Three output lengths across seven concurrency levels |
| `gpu-memory-scaling` | 28 | Four GPU memory targets across seven concurrency levels |
| `model-length-scaling` | 28 | Four model-length limits across seven concurrency levels |
| `scheduler-batching` | 42 | Six sequence/batched-token configurations across seven concurrency levels |
| `streaming-comparison` | 14 | Streaming and non-streaming across seven concurrency levels |
| **Complete suite** | **189** | All named profiles |

Profiles are hypothesis-driven and execute sequentially. They are not run in parallel.

At the default 10 minutes of request activity per case, the complete suite contains 31.5 hours of warmup and measurement time. Predictor restarts and stabilization add further runtime.

## Prompt and Output Control

The load generator builds prompts from the committed capacity-engineering corpus using the pinned tokenizer. For every request it:

- Adds a unique SHA-256 fingerprint at the beginning of the prompt to avoid shared initial prefix-cache blocks.
- Selects a deterministic offset into the tokenized corpus.
- Repeats corpus tokens when necessary for long prompts.
- Re-encodes and adjusts the prompt until it has the exact requested token count.

The request asks vLLM for the exact output size using:

- `max_tokens=<requested output tokens>`
- `min_tokens=<requested output tokens>`
- `ignore_eos=true`

Actual prompt and output token counts are recorded. The output-length compliance rate shows how often successful requests returned the requested number of output tokens.

## Plan a Run

Planning expands and validates profiles without changing Kubernetes resources or starting a benchmark:

```bash
bash benchmarks/inference-performance/run-benchmark.sh plan
```

Plan one profile:

```bash
bash benchmarks/inference-performance/run-benchmark.sh plan concurrency-saturation
```

The full plan should report 189 cases.

## Run the Benchmark

Run one profile from the repository root:

```bash
bash benchmarks/inference-performance/run-benchmark.sh concurrency-saturation
```

Run the complete suite:

```bash
bash benchmarks/inference-performance/run-benchmark.sh all
```

On macOS, prevent sleep during a long run:

```bash
caffeinate -dimsu \
  bash benchmarks/inference-performance/run-benchmark.sh all
```

### Short smoke test

Use reduced warmup and measurement durations before committing to a long run:

```bash
WARMUP_SECONDS=10 \
DURATION_SECONDS=30 \
POST_READY_SETTLE_SECONDS=30 \
bash benchmarks/inference-performance/run-benchmark.sh concurrency-saturation
```

This still executes all seven concurrency cases in the profile. It is intended to validate routing, authentication, tokenizer loading, result generation, and metric queries rather than produce trustworthy capacity conclusions.

## Runtime Overrides

Common environment variables are:

| Variable | Default | Purpose |
|---|---|---|
| `INFER_API_KEY` | `notforprod` | Envoy bearer credential |
| `INFER_URL` | `http://127.0.0.1:18080/v1/completions` | OpenAI-compatible completion endpoint |
| `PROM_URL` | `http://127.0.0.1:9090` | Prometheus endpoint |
| `WARMUP_SECONDS` | `120` | Warmup duration per case |
| `DURATION_SECONDS` | `480` | Measurement duration per case |
| `REQUEST_TIMEOUT_SECONDS` | `380` | Per-request load-generator timeout |
| `POST_READY_SETTLE_SECONDS` | `240` | Stabilization delay after predictor readiness |
| `ENVOY_SERVICE` | discovered | Explicit generated Envoy Service override |
| `AUTO_PORT_FORWARD_INFER` | `true` | Manage the Envoy port-forward |
| `AUTO_PORT_FORWARD_PROM` | `true` | Manage the Prometheus port-forward |
| `MODEL_ID` | `/models` | Model identifier sent in API requests |

The timeout chain is ordered as load generator (380 seconds), Envoy (420 seconds), and NLB (480 seconds). Requests that exceed 380 seconds are classified consistently as client-side benchmark timeouts, while the gateway and load balancer remain available beyond that cutoff.

Example using externally managed endpoints:

```bash
INFER_URL="https://inference.example.com/v1/completions" \
INFER_API_KEY="${API_KEY}" \
PROM_URL="https://prometheus.example.com" \
AUTO_PORT_FORWARD_INFER=false \
AUTO_PORT_FORWARD_PROM=false \
bash benchmarks/inference-performance/run-benchmark.sh concurrency-saturation
```

## Execution Flow

For every engine, GPU-memory, and model-length combination, the orchestrator:

1. Validates all profile values against the benchmark matrix.
2. Scales the KServe-owned predictor Deployment to zero.
3. Waits for the old predictor pod to terminate.
4. Replaces the `kserve-container` arguments on the InferenceService.
5. Scales the predictor Deployment back to one replica.
6. Waits for the InferenceService to become Ready and allows it to stabilize.
7. Resolves the predictor node for DCGM metric scoping.
8. Ensures the authenticated Envoy endpoint is available.
9. Runs warmup and measurement phases for each workload case.
10. Calculates client-side statistics from request-level data.
11. Ensures Prometheus is available and queries the exact measurement window.
12. Appends one normalized row to the unified CSV.

The runner mutates the InferenceService and directly scales its generated predictor Deployment. It does not restore the baseline vLLM arguments after the suite completes. Record or reapply the desired deployment configuration after benchmarking.

## Result Artifacts

Generated files are written under [benchmarks/inference-performance/results](../../benchmarks/inference-performance/results):

```text
results/
  benchmark-results.csv
  benchmark.log
  request-level/
    <run-and-case-key>.jsonl
    <run-and-case-key>-summary.json
```

- `benchmark-results.csv` is the normalized aggregate dataset. Its 64-field schema is identical for completed and startup-failed cases.
- `benchmark.log` contains timestamped orchestrator and subprocess output.
- Each JSONL file contains one record per measured request.
- Each summary JSON contains the measurement bounds, workload settings, and request totals used by the statistics and metrics scripts.

The result and log files are appended across suite invocations. `run_id` distinguishes separate invocations. Archive or remove previous generated results before a run when a clean dataset is required.

Generated result directories are ignored by Git and should not be committed.

## Measurements

The unified CSV contains 64 fields:

- 12 experiment and configuration fields.
- 3 case-status fields: `case_status`, `error_type`, and `error_message`.
- 49 request, latency, throughput, vLLM, Prometheus, and GPU telemetry fields.

The fields cover:

- Experiment identity, hypothesis, engine settings, workload shape, and concurrency.
- Case completion status, error type, and error message.
- Attempted requests, successful requests, errors, and success/error rates.
- Attempted and successful requests per second.
- Actual prompt, output, and total token throughput.
- Success-only latency averages and percentiles.
- Failure-duration statistics kept separate from successful latency.
- Streaming TTFT and time-per-output-token statistics.
- Requested output-length compliance.
- vLLM output-token counters, preemptions, and prefix-cache hits.
- Running and waiting request levels.
- KV-cache utilization.
- GPU utilization, framebuffer use, tensor activity, and DRAM activity.

Unavailable measurements are written as empty values rather than zero. In particular, non-streaming requests do not provide TTFT, so their TTFT and per-output-token cells remain empty.

A successful case is recorded with `case_status=completed`; `error_type` and `error_message` are empty. Its request, latency, throughput, vLLM, Prometheus, and GPU fields are populated, except measurements that do not apply, such as TTFT for non-streaming requests.

If the `0.95` GPU-memory configuration cannot start, each skipped workload case is recorded with `case_status=startup_failed` and `error_type=configuration_startup`; performance and telemetry fields remain empty. The runner restores `0.90` and continues.

Prometheus counters use `increase()` over the exact measurement duration and are evaluated at the recorded benchmark end time. DCGM queries are scoped to the Kubernetes node hosting the predictor.

## Validation

Validate source syntax before running:

```bash
bash -n benchmarks/inference-performance/run-benchmark.sh
python3 -m py_compile \
  benchmarks/inference-performance/python/loadgen.py \
  benchmarks/inference-performance/python/statistic.py \
  benchmarks/inference-performance/python/metrics.py
```

After a smoke test, confirm:

1. `benchmark-results.csv` contains one row per completed case and all rows have the same schema.
2. Request-level JSONL and summary JSON files exist for each completed case.
3. Successful requests report status `200`.
4. Unexpected `401` responses are absent.
5. Any `429` responses correspond to the configured Envoy rate limit rather than model-server failure.
6. Successful latency does not include failed-request durations.
7. Prometheus fields contain data for the measurement window.
8. GPU metrics correspond to the predictor node.
9. Streaming rows contain TTFT values and non-streaming rows leave those fields empty.

## Troubleshooting

### InferenceService does not become Ready

```bash
kubectl -n llm-serving describe inferenceservice deepseek-r1-14b
kubectl -n llm-serving get pods -o wide
kubectl -n llm-serving get events --sort-by=.lastTimestamp | tail -n 40
kubectl -n llm-serving logs deployment/deepseek-r1-14b-predictor
```

Check whether the selected GPU-memory or maximum-model-length setting prevents vLLM from starting.

### Envoy Service discovery fails

Inspect the generated data-plane Services:

```bash
kubectl -n envoy-gateway-system get services
```

If zero or multiple names match the expected prefix, set the intended Service explicitly:

```bash
ENVOY_SERVICE="<generated-envoy-service>" \
bash benchmarks/inference-performance/run-benchmark.sh concurrency-saturation
```

The Envoy port-forward log is `/tmp/benchmark-portforward.log`.

### Requests return 401

The API key does not match the credential accepted by the Envoy SecurityPolicy. Set the active value through `INFER_API_KEY` and retry. Do not bypass Envoy with a predictor port-forward for benchmark runs.

### Requests return 429

The Envoy route currently applies a local rate limit of 100 requests per second per Envoy replica. A `429 Too Many Requests` response means Envoy rejected the request before it reached vLLM. Keep these failures in the result set when measuring the complete serving path.

### Prometheus is unavailable

Inspect `/tmp/benchmark-prometheus-portforward.log`, then verify the Service and readiness endpoint:

```bash
kubectl -n monitoring get svc kube-prometheus-stack-prometheus
curl -f http://127.0.0.1:9090/-/ready
```

The runner treats required telemetry as mandatory. Missing required Prometheus data fails the case instead of silently writing zero.

### GPU metrics are empty

Confirm that DCGM exporter exposes metrics for the predictor node and that its `Hostname` label matches the pod's `.spec.nodeName`:

```bash
kubectl -n llm-serving get pod \
  -l serving.kserve.io/inferenceservice=deepseek-r1-14b \
  -o wide
```

### Tokenizer cannot be loaded

Activate the environment containing `transformers`, verify the pinned tokenizer revision is accessible, and ensure the Hugging Face cache is populated before an offline run.

### Benchmark is interrupted

The runner stops port-forward processes that it started. Completed CSV rows and request-level artifacts remain available. A restarted invocation receives a new `run_id`; it does not resume from the interrupted case.
