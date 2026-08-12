# vLLM Prometheus Metrics Reference

## Purpose
Quick reference for core vLLM runtime metrics used during tuning, overload testing, and incident triage.

This file complements GPU/DCGM metrics from [dcgm-prometheus-metrics-reference.md](dcgm-prometheus-metrics-reference.md).

## Scope
These metrics focus on:
- KV cache pressure
- scheduler pressure
- latency decomposition (prefill/decode/TTFT)
- throughput behavior
- prefix cache efficiency

## Metrics and Practical Queries

## Core Latency Query Pack 
Use these first before exploring the full metric set.

### TTFT p95
```promql
histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))
```

### End-to-End Latency p95
```promql
histogram_quantile(0.95, sum by (le) (rate(vllm:request_inference_time_seconds_bucket[5m])))
```

### End-to-End Latency p99
```promql
histogram_quantile(0.99, sum by (le) (rate(vllm:request_inference_time_seconds_bucket[5m])))
```

### Prefill p95
```promql
histogram_quantile(0.95, sum by (le) (rate(vllm:request_prefill_time_seconds_bucket[5m])))
```

### Decode p95
```promql
histogram_quantile(0.95, sum by (le) (rate(vllm:request_decode_time_seconds_bucket[5m])))
```

## Other Metrics and Practical Queries

### 1. KV Cache Usage
- Metric: `vllm:kv_cache_usage_perc`
- Meaning: percentage of KV cache currently in use.
- Question: how full is KV cache?
- Practical query:
```promql
max by (pod) (vllm:kv_cache_usage_perc{namespace="llm-serving", pod=~"vllm-tinyllama-.*"})
```
- What this query is looking for:
	- Current KV cache pressure per pod.
	- Persistent values above about 85 to 90 percent mean you are near memory pressure and preemptions can increase.

### 2. Preemption Count
- Metric: `vllm:num_preemptions_total`
- Meaning: cumulative number of request preemptions due to KV pressure.
- Question: how often is vLLM evicting/recomputing?
- Practical query:
```promql
sum by (pod) (increase(vllm:num_preemptions_total{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m]))
```
- What this query is looking for:
	- New preemptions in the last 5 minutes, not lifetime total.
	- Any sustained non-zero trend indicates KV pressure is forcing request evictions or recompute.

### 3. Generation Throughput (Tokens per Second)
- Metric: `vllm:generation_tokens_total`
- Meaning: cumulative generated output tokens.
- Question: how fast is token generation?
- Practical query:
```promql
sum by (pod) (rate(vllm:generation_tokens_total{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[1m]))
```
- What this query is looking for:
	- Real-time output throughput.
	- Throughput flattening while queue and latency rise means the system is saturated.

### 4. Running Requests
- Metric: `vllm:num_requests_running`
- Meaning: requests currently executing.
- Question: how many requests are actively being processed?
- Practical query:
```promql
max by (pod) (vllm:num_requests_running{namespace="llm-serving", pod=~"vllm-tinyllama-.*"})
```
- What this query is looking for:
	- In-flight scheduler concurrency.
	- If running requests stay capped while waiting requests keep rising, concurrency limits are bottlenecking.

### 5. Waiting Requests
- Metric: `vllm:num_requests_waiting`
- Meaning: requests waiting in scheduler queue.
- Question: how many requests are queued?
- Practical query:
```promql
max by (pod) (vllm:num_requests_waiting{namespace="llm-serving", pod=~"vllm-tinyllama-.*"})
```
- What this query is looking for:
	- Queue depth right now.
	- Sustained growth indicates demand exceeds effective serving capacity.

### 6. Prefill Time
- Metric: `vllm:request_prefill_time_seconds_sum`
- Meaning: cumulative prefill time across requests.
- Question: how much time is spent processing prompt prefill?
- Rate query:
```promql
sum by (pod) (rate(vllm:request_prefill_time_seconds_sum{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m]))
```
- If companion `*_count` exists, average prefill latency per request:
```promql
sum by (pod) (rate(vllm:request_prefill_time_seconds_sum{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m]))
/
clamp_min(sum by (pod) (rate(vllm:request_prefill_time_seconds_count{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m])), 1e-9)
```
- What this query is looking for:
	- Prefill contribution to latency.
	- Rising average prefill latency often points to longer prompts, larger max-model-len, or overloaded batching.

### 7. End-to-End Inference Time
- Metric: `vllm:request_inference_time_seconds_sum`
- Meaning: cumulative end-to-end inference time.
- Question: how much total serving time is being consumed?
- Rate query:
```promql
sum by (pod) (rate(vllm:request_inference_time_seconds_sum{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m]))
```
- If companion `*_count` exists, average end-to-end latency:
```promql
sum by (pod) (rate(vllm:request_inference_time_seconds_sum{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m]))
/
clamp_min(sum by (pod) (rate(vllm:request_inference_time_seconds_count{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m])), 1e-9)
```
- What this query is looking for:
	- Service time consumed by requests.
	- If this increases faster than throughput, each request is getting more expensive under current load or config.

### 8. Time To First Token (TTFT)
- Metric: `vllm:time_to_first_token_seconds_sum`
- Meaning: cumulative TTFT across requests.
- Question: how much total first-token waiting time users experienced?
- Rate query:
```promql
sum by (pod) (rate(vllm:time_to_first_token_seconds_sum{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m]))
```
- For p99 TTFT (recommended), use histogram buckets:
```promql
histogram_quantile(0.99, sum by (le, pod) (rate(vllm:time_to_first_token_seconds_bucket{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m])))
```
- What this query is looking for:
	- User-perceived first-token delay, especially tail latency with p99.
	- p99 jumping while throughput is flat is an early warning of queueing or memory pressure.

### 9. Prefix Cache Hits
- Metric: `vllm:prefix_cache_hits_total`
- Meaning: cumulative successful prefix-cache hits.
- Question: is repeated-prefix reuse happening?
- Practical query:
```promql
sum by (pod) (increase(vllm:prefix_cache_hits_total{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m]))
```
- What this query is looking for:
	- Prefix-cache reuse effectiveness over the recent window.
	- Low or zero hits during repeated-prefix workloads means caching is not helping and TTFT can stay higher than expected.

### 10. Prefix Cache Query Creation Timestamp
- Metric: `vllm:prefix_cache_queries_created`
- Meaning: timestamp metric for metric object creation.
- Question: usually not useful for operations.
- Recommendation: do not use in dashboards.
- What this query is looking for:
	- Mostly metadata, not performance behavior.
	- Keep it out of tuning dashboards.

### 11. Requested Max Tokens
- Metric: `vllm:request_params_max_tokens_sum`
- Meaning: sum of max_tokens requested by clients.
- Question: what generation limits are clients asking for?
- Rate query:
```promql
sum by (pod) (rate(vllm:request_params_max_tokens_sum{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m]))
```
- If companion `*_count` exists, average requested max_tokens:
```promql
sum by (pod) (rate(vllm:request_params_max_tokens_sum{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m]))
/
clamp_min(sum by (pod) (rate(vllm:request_params_max_tokens_count{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m])), 1e-9)
```
- What this query is looking for:
	- Client demand profile for completion length.
	- Rising requested max_tokens usually increases decode load and can worsen tail latency.

### 12. Prompt Tokens
- Metric: `vllm:request_prompt_tokens_sum`
- Meaning: cumulative prompt tokens received.
- Question: how much input-token load is hitting the system?
- Practical query:
```promql
sum by (pod) (rate(vllm:request_prompt_tokens_sum{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[1m]))
```
- What this query is looking for:
	- Input-token arrival rate.
	- High prompt-token rate with rising prefill latency indicates prompt-heavy pressure.

## Minimal Must-Have Dashboard Set
- `vllm:kv_cache_usage_perc`
- `increase(vllm:num_preemptions_total[5m])`
- `rate(vllm:generation_tokens_total[1m])`
- `vllm:num_requests_running`
- `vllm:num_requests_waiting`
- `histogram_quantile(0.99, rate(vllm:time_to_first_token_seconds_bucket[5m]))`

## Troubleshooting Notes
- If latency quantiles show `NaN`, check request activity first:
```promql
sum(rate(vllm:time_to_first_token_seconds_count{namespace="llm-serving", pod=~"vllm-tinyllama-.*"}[5m]))
```
- If this returns `0`, no usable observations exist in the selected window.
- For low-traffic windows, temporarily widen to `[30m]`.
