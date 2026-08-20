# Inference Performance Benchmark Report

**Run date:** 2026-08-17  
**Model:** DeepSeek-R1-Distill-Qwen-14B-AWQ  
**Serving path:** Load generator -> Envoy AI Gateway -> KServe -> vLLM -> one GPU-backed predictor

## Executive Summary

This report establishes an initial capacity envelope for the DeepSeek R1 14B service. Under the standard 1,024-input-token and 128-output-token workload, one predictor reached a stable ceiling of approximately 1.5 to 1.6 successful requests per second. Increasing concurrency beyond 20 delivered little additional throughput but materially increased queueing and tail latency.

At concurrency 40, throughput was 1.63 successful requests per second, but p99 latency reached 35.5 seconds and the scheduler observed up to 25 waiting requests. This saturation point is used to derive the secondary p99 autoscaling guardrail of 30 seconds. Queueing first appeared at concurrency 5, supporting the primary autoscaling trigger of two waiting requests.

Longer outputs reduced request throughput and increased latency. The largest tested output, 1,024 tokens, reduced completed-request throughput to 0.45 requests per second at concurrency 20 and raised p99 latency to 48.8 seconds. The evidence supports scaling on queue pressure before tail latency becomes visible to users.

## Scope and Method

The suite is described in the [benchmark runbook](../runbooks/benchmark-runbook.md). It sends non-streaming OpenAI-compatible completion requests through the authenticated Envoy Gateway path; results therefore include gateway authentication, routing, rate limiting, and transport overhead.

The tested predictor configuration was:

| Setting | Value |
|---|---:|
| GPU memory utilization | 90% |
| Maximum model length | 15,000 tokens for concurrency and output tests; 40,000 for prompt tests |
| Maximum sequences | 40 for concurrency tests; 20 for output tests; 16 for prompt tests |
| Maximum batched tokens | 2,048 |
| Measurement duration per case | 480 seconds |
| Warmup duration per case | 30 seconds |

The request generator records client-side request outcomes, token counts, and latency percentiles. The metrics collector queries Prometheus for the exact measurement window and records vLLM scheduler, KV-cache, token-generation, DCGM GPU, and GPU-memory metrics. The implementation is in [loadgen.py](../../benchmarks/inference-performance/python/loadgen.py), [statistic.py](../../benchmarks/inference-performance/python/statistic.py), and [metrics.py](../../benchmarks/inference-performance/python/metrics.py).

Prompts are constructed to the requested token length from the committed corpus and receive a unique fingerprint to avoid shared prefix-cache effects. Successful requests are configured to return the requested output length. This makes prompt and output token counts controlled workload variables rather than approximate user-text sizes.

Raw result files are generated locally and intentionally excluded from Git. Reproduce the saturation experiment with:

```bash
bash benchmarks/inference-performance/run-benchmark.sh concurrency-saturation
```

## Results

### Concurrency Saturation

This profile held request shape constant at 1,024 input tokens and 128 output tokens while increasing concurrency. Every case completed with a 100% success rate.

| Concurrency | Successful requests/s | Total tokens/s | p95 latency | p99 latency | Waiting requests, max |
|---:|---:|---:|---:|---:|---:|
| 1 | 0.33 | 381 | 3.1s | 3.1s | 0 |
| 5 | 0.98 | 1,134 | 5.1s | 5.2s | 2 |
| 10 | 1.32 | 1,518 | 8.0s | 8.5s | 5 |
| 20 | 1.54 | 1,778 | 13.9s | 15.5s | 7 |
| 40 | 1.63 | 1,879 | 25.9s | 35.5s | 25 |

Throughput grew quickly through concurrency 20, then increased by only 0.09 successful requests per second between concurrency 20 and 40. In contrast, p99 latency more than doubled and maximum queue depth grew from 7 to 25 requests. The GPU was fully utilized in every concurrency case, GPU memory remained near 87% utilized, and no vLLM preemptions were recorded.

**Finding:** A single predictor should be treated as saturated around 20 concurrent requests for this request shape. Concurrency 40 is a throughput plateau with unacceptable tail latency, not a useful operating target.

### Output-Length Scaling

This profile held the prompt at 1,024 tokens and concurrency at 20 while increasing the requested output length.

| Requested output tokens | Successful requests/s | Total tokens/s | p95 latency | p99 latency | Waiting requests, max |
|---:|---:|---:|---:|---:|---:|
| 128 | 1.54 | 1,772 | 14.8s | 15.8s | 8 |
| 512 | 0.78 | 1,202 | 27.0s | 28.1s | 5 |
| 1,024 | 0.45 | 928 | 45.2s | 48.8s | 3 |

All cases completed successfully. Longer generations reduced completed-request throughput because the decoder remains occupied for more output tokens per request. Output-token throughput increased from 197 to 470 tokens per second, but total token throughput fell as request completion slowed.

**Finding:** A request-rate target alone is insufficient for capacity planning. Output length changes both the achievable request rate and the user-visible latency envelope.

### Prompt-Length Scaling

The 128-token prompt baseline completed successfully at both tested concurrency levels.

| Prompt tokens | Concurrency | Successful requests/s | p95 latency | p99 latency | Waiting requests, max |
|---:|---:|---:|---:|---:|
| 128 | 1 | 0.38 | 2.7s | 3.0s | 0 |
| 128 | 10 | 2.86 | 4.3s | 5.4s | 0 |
| 4,096 | 10 | 0.42 | 25.9s | 29.6s | 7 |

The 4,096-token prompt at concurrency 1 recorded zero successful responses and must be rerun. It is excluded from performance conclusions. The 4,096-token prompt at concurrency 10 completed successfully but showed substantial prefill cost, queueing, and 66% average KV-cache utilization.

**Finding:** Prompt length is a material capacity dimension. The short-prompt baseline does not represent the latency or queue behavior of multi-thousand-token prompts.

## Scheduler and Resource Interpretation

The concurrency-saturation profile kept the GPU at 100% utilization across all tested concurrency levels. GPU memory use remained approximately 86% to 87%, and vLLM recorded zero preemptions. This indicates that the standard workload saturated available GPU execution capacity before exhausting the KV cache or forcing scheduler preemption.

KV-cache use did increase with workload pressure: it averaged 2% at concurrency 1 and 78% at concurrency 40 in the standard workload. The completed 4,096-token prompt case reached 66% average KV-cache use at concurrency 10. These measurements support treating long prompts as a separate capacity class, but they do not establish a KV-cache exhaustion limit.

The benchmark generated no shared prefix-cache hits. Results therefore represent requests without reusable prompt prefixes and should not be used to claim benefits from prefix caching, retrieval augmentation, or repeated system prompts.

## Capacity Recommendations

- Use one GPU-backed predictor as the minimum warm capacity. Model and GPU-node startup are too slow to make scale-from-zero appropriate for this service.
- Treat approximately 1.5 successful requests per second as the practical per-replica planning capacity for the standard 1,024/128-token workload, not the 1.63 requests per second observed at saturation.
- Use `vllm:num_requests_waiting > 2` as the primary scale-out signal. Queueing appeared before severe tail latency in the saturation test.
- Use p99 inference latency above 30 seconds as the secondary scale-out guardrail. The p99 result crossed that threshold only at the concurrency-40 saturation point.
- Size or limit workloads by prompt and output token budgets as well as concurrent requests. Long outputs and long prompts have materially different capacity envelopes.

The implemented trigger thresholds and replica behavior are documented in [ADR 002](../decisions/002-benchmark-derived-autoscaling-triggers.md) and configured in the [KEDA ScaledObject](../../kubernetes/autoscaling/scaledobject.yaml).

## Limitations and Next Experiments

- These results represent one model, one GPU-backed predictor, non-streaming completions, and the tested vLLM configurations. They are not a general capacity claim for all request shapes or GPU types.
- The test workload deliberately avoids shared prompt prefixes. It does not represent applications where prefix caching materially improves prefill work.
- Repeat the failed 4,096-token/concurrency-1 case before expanding prompt-length conclusions.
- Complete the active scheduler-batching profile to compare `max_num_seqs` and `max_num_batched_tokens` settings at the saturation workload.
- Run the currently disabled streaming, GPU-memory, and model-length profiles before selecting a separate streaming capacity envelope.
- Validate KEDA scale-out end to end, including model mount time, pod readiness, GPU-node provisioning, and request latency during scaling. The current report measures one ready replica; it does not yet measure scale-event recovery time.
- Re-run the benchmark whenever the model revision, GPU type, vLLM version, scheduler settings, request shape, or cache architecture changes.