# ADR 002: Benchmark-Derived Autoscaling Triggers

**Status:** Accepted

## Context

The DeepSeek R1 14B service needs to scale before sustained demand causes excessive queueing, while avoiding unnecessary GPU replicas during short traffic spikes. The [ScaledObject](../../kubernetes/autoscaling/scaledobject.yaml) uses KEDA Prometheus triggers, so its thresholds should be derived from observed vLLM behavior rather than chosen arbitrarily.

Benchmark artifacts are generated locally and are intentionally excluded from Git. A reader can reproduce the evidence by following the [benchmark runbook](../runbooks/benchmark-runbook.md) and running:

```bash
bash benchmarks/inference-performance/run-benchmark.sh concurrency-saturation
```

The benchmark holds the deployed vLLM configuration constant and tests concurrency levels of 1, 5, 10, 20, and 40 with 1,024-token prompts and 128-token outputs. It sends traffic through the authenticated Envoy Gateway path and records client latency together with vLLM queue metrics.

The most recent completed run produced these relevant observations for one GPU-backed predictor replica:

| Concurrency | Successful requests/s | p99 latency | Maximum waiting requests |
|---:|---:|---:|---:|
| 1 | 0.33 | 3.1s | 0 |
| 5 | 0.98 | 5.2s | 2 |
| 10 | 1.32 | 8.5s | 5 |
| 20 | 1.54 | 15.5s | 7 |
| 40 | 1.63 | 35.5s | 25 |

Throughput approaches a ceiling near 1.5 to 1.6 successful requests per second per replica, while queueing begins at concurrency 5 and tail latency breaches 30 seconds at concurrency 40.

## Decision

I use three independent KEDA Prometheus scale signals. KEDA/HPA calculates a desired replica count for each trigger and applies the largest result; the configuration does not assign a priority order to queue depth, KV-cache utilization, or p99 latency.

The queue-depth signal has a threshold of 2 waiting requests:

```promql
sum(vllm:num_requests_waiting{
  namespace="llm-serving",
  pod=~"deepseek-r1-14b.*"
})
```

Queue depth is direct evidence that requests are waiting for active replica capacity. The threshold is intentionally small because the benchmark first observes queued requests at concurrency 5, before p99 latency becomes severe.

The KV-cache signal uses the sum of the raw per-pod utilization fractions with a threshold of 0.75:

```promql
sum(vllm:kv_cache_usage_perc{
  namespace="llm-serving",
  pod=~"deepseek-r1-14b.*"
})
```

The metric reports a fraction from 0 to 1, so the query must not multiply it by 100. Summing the fractions measures aggregate cache occupancy across predictor replicas instead of averaging it. The 0.75 threshold is an initial scale signal to validate during end-to-end scaling tests; cache occupancy can be driven by a small number of long prompts and is not, by itself, proof of queued demand.

The p99 inference-latency signal has a threshold of 30 seconds:

```promql
histogram_quantile(
  0.99,
  sum by (le) (
    rate(vllm:request_inference_time_seconds_bucket{
      namespace="llm-serving",
      pod=~"deepseek-r1-14b.*"
    }[5m])
  )
)
```

The p99 signal is a user-experience guardrail. It protects the slowest one percent of requests when other pressure signals do not prevent tail latency from breaching the 30-second target. Response latency is observed only after a client has waited, so it remains a lagging indicator even though it has equal scaling authority in the HPA calculation.

I retain one minimum replica because model startup and GPU provisioning are slow compared with request arrival. I cap the service at six replicas because each predictor requests one GPU, and the GPU NodePools allow a combined maximum of six GPUs. I use a 15-second polling interval, scale up by at most 100% every 30 seconds, and scale down more slowly after a five-minute stabilization window to avoid GPU replica churn.

## Consequences

- Any one of the queue-depth, KV-cache, or p99 triggers can raise the desired replica count. The HPA uses the largest desired count, not a priority order.
- The queue-depth signal should add capacity when requests are waiting. The KV-cache signal may raise capacity before a queue forms, while the p99 signal can react only after completed requests expose a latency breach.
- The KV-cache threshold is a hypothesis, not an established cache-exhaustion boundary. Validate it under sustained multi-replica load and revise it if it does not improve scale-out behavior or causes unnecessary replicas for long-context requests.
- The trigger values are valid for the benchmarked model, vLLM arguments, request shape, GPU type, and one-GPU-per-predictor deployment. Re-run the concurrency-saturation benchmark after changing any of those inputs and revise this ADR and the [ScaledObject](../../kubernetes/autoscaling/scaledobject.yaml) when the saturation point changes.
- The six-replica cap is an infrastructure ceiling, not a throughput promise. It requires six schedulable GPUs and model storage that supports predictor replicas across nodes.