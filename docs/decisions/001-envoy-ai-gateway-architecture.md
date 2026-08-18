# ADR 001: Envoy AI Gateway Architecture

**Status:** Accepted

## Context

The platform needs a public, OpenAI-compatible entry point for the DeepSeek R1 14B inference service. The entry point must provide authenticated access, request protection, streaming-safe timeouts, and a way to control token consumption without placing those concerns in the model-serving workload.

## Decision

I use Envoy Gateway and Envoy AI Gateway as the traffic-management layer in front of the KServe predictor.

```text
Client
  -> AWS Network Load Balancer
  -> Envoy Gateway data plane
  -> API-key authentication and traffic policies
  -> Envoy AI Gateway route and quota policy
  -> DeepSeek R1 14B KServe predictor
```

The [GatewayClass and Gateway](../../kubernetes/gateway/gateway.yaml) create the HTTP entry point in the `llm-serving` namespace. The [EnvoyProxy](../../kubernetes/gateway/envoy-proxy.yaml) configures its Kubernetes service as an internet-facing AWS Network Load Balancer.

The [AIGatewayRoute](../../kubernetes/gateway/route.yaml) sends AI traffic to the [AIServiceBackend and Backend](../../kubernetes/gateway/backend.yaml), which resolve to the internal KServe predictor service. The route uses a 420-second request timeout to allow long-running inference and streaming responses.

The [SecurityPolicy](../../kubernetes/gateway/auth.yaml) validates an API key from the `Authorization` header, removes the supplied credential before forwarding, and sets the trusted `x-client-id` header from the authenticated key identity. The current `development-client` key is intentionally a non-production demonstration credential.

The [BackendTrafficPolicy](../../kubernetes/gateway/rate-limit.yaml) limits incoming traffic to 100 requests per second. The [ClientTrafficPolicy](../../kubernetes/gateway/traffic-policy.yaml) sets a 420-second stream idle timeout and a 50 MiB connection buffer limit.

The [QuotaPolicy](../../kubernetes/gateway/quota-policy.yaml) applies model-aware token accounting. It provides a 1 million token rolling-day client bucket, keyed by the trusted `x-client-id` header, plus a 100 million token rolling-day default bucket. Envoy AI Gateway's current shared quota mode permits a request while at least one matching bucket has capacity. Therefore, after a client consumes its 1 million token allowance, it may consume remaining capacity from the 100 million token platform pool.

Quota counters are stored in Redis. The [Redis namespace](../../kubernetes/namespaces/redis-ns.yaml), [PersistentVolumeClaim](../../kubernetes/gateway/quota-redis-pvc.yaml), [headless Service](../../kubernetes/gateway/quota-redis-svc.yaml), and [StatefulSet](../../kubernetes/gateway/quota-redis-statefulset.yaml) provide a single persistent Redis instance. The PVC uses the cluster's `auto-ebs-gp3` storage class, defined in [storage_class.tf](../../terraform/modules/monitoring/storage_class.tf). The Envoy Gateway Helm values configure the Redis-backed global rate-limit service in [main.tf](../../terraform/modules/envoy_ai_gateway/main.tf).

## Rationale

- I chose gateway policy to separate access control, routing, and quota enforcement from the KServe model workload.
- I use API-key-derived client identity so callers cannot select another client's quota bucket.
- I use the local request-rate limit for immediate abuse protection and token quotas to constrain accumulated model usage.
- I chose a shared platform pool to avoid reserving unused capacity for inactive clients and to improve GPU utilization.
- Redis provides a single counter store that can be used consistently if the gateway data plane scales beyond one replica.
- I reused the existing encrypted EBS `gp3` storage class to provide durable storage without adding another storage policy for the demo Redis workload.

## Consequences

- I do not enforce a strict 1 million token maximum per client. Each client receives a preferred 1 million token allowance and can borrow unused capacity from the shared 100 million token pool.
- The quota window is rolling one day (`1d`), not a calendar-day or monthly billing reset.
- The StatefulSet is a single-replica proof-of-concept dependency. It has no high availability, authentication, TLS, NetworkPolicy, backup, or managed failover.