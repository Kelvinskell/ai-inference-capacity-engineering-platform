# Envoy Gateway Operations

Quick checks for Envoy Gateway, Envoy AI Gateway, and the vLLM route.

## Context

```bash
# Reuse the deployed namespaces and the stable Gateway ownership label.
# Generated Envoy resource names contain hashes and must not be hard-coded.
NS=llm-serving
EG_NS=envoy-gateway-system
AI_NS=envoy-ai-gateway-system
GW=envoy-ai-gateway
SELECTOR="gateway.envoyproxy.io/owning-gateway-name=$GW"
```

## Controllers

```bash
# Confirm both control-plane controllers are running before checking routes.
kubectl get pods -n "$EG_NS"
kubectl get pods -n "$AI_NS"

# Check Envoy Gateway reconciliation, Gateway API, RBAC, and provisioning errors.
kubectl logs -n "$EG_NS" \
  -l app.kubernetes.io/instance=envoy-gateway \
  --all-containers --tail=100

# Check AI Gateway route translation and AI-specific resource errors.
kubectl logs -n "$AI_NS" \
  -l app.kubernetes.io/instance=envoy-ai-gateway \
  --all-containers --tail=100
```

## Gateway

```bash
# Confirm the GatewayClass exists and is accepted by the Envoy controller.
kubectl get gatewayclass

# Check whether the Gateway has an address and Accepted/Programmed conditions.
kubectl get gateway -n "$NS"

# Inspect listener conditions and events when the Gateway is not programmed.
kubectl describe gateway "$GW" -n "$NS"

# Confirm the NLB/data-plane configuration and stream timeout policy exist.
kubectl get envoyproxy,clienttrafficpolicy -n "$NS"
```

## AI Gateway

```bash
# Confirm the AI route and backend chain exists in the application namespace.
kubectl get aigatewayroute,aiservicebackend,backend -n "$NS"

# Inspect acceptance, resolved references, and controller messages.
kubectl describe aigatewayroute deepseek-r1-14b -n "$NS"

# Confirm the AI controller generated the HTTPRoute consumed by Envoy Gateway.
kubectl get httproute -n "$NS"
```

## Policies

```bash
# Confirm authentication and rate-limit policies exist.
kubectl get securitypolicy,backendtrafficpolicy -n "$NS"

# Verify the API-key policy is accepted and attached to the intended route.
kubectl describe securitypolicy envoy-ai-gateway-api-key -n "$NS"

# Verify the rate-limit policy is accepted and attached to the intended route.
kubectl describe backendtrafficpolicy deepseek-r1-14b-rate-limit -n "$NS"
```

## Generated Envoy Resources

```bash
# Confirm Envoy Gateway created the data-plane Deployment, Pods, and Service.
kubectl get svc,pods,deploy -n "$EG_NS" -l "$SELECTOR" -o wide

# Discover the generated Service through its stable ownership label.
ENVOY_SVC="$(kubectl get svc \
  -n "$EG_NS" \
  -l "$SELECTOR" \
  -o jsonpath='{.items[0].metadata.name}')"

# Inspect NLB annotations, endpoints, events, and AWS finalizer state.
kubectl describe svc "$ENVOY_SVC" -n "$EG_NS"

# Check Envoy data-plane logs for upstream, routing, and policy failures.
kubectl logs -n "$EG_NS" -l "$SELECTOR" --all-containers --tail=100
```

## NLB Endpoint

```bash
# Read the public NLB hostname from the generated Envoy Service status.
# An empty value means load-balancer provisioning is not complete or failed.
NLB="$(kubectl get svc \
  "$ENVOY_SVC" \
  -n "$EG_NS" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

echo "$NLB"
```

## KServe And vLLM

```bash
# Confirm the InferenceService, predictor Pods, and backend Service are ready.
kubectl get inferenceservice,pods,svc -n "$NS" -o wide

# Inspect KServe readiness conditions and deployment events.
kubectl describe inferenceservice deepseek-r1-14b -n "$NS"

# Check model loading, GPU allocation, OOM, and inference server errors.
kubectl logs -n "$NS" \
  -l serving.kserve.io/inferenceservice=deepseek-r1-14b \
  --all-containers --tail=100
```

## Request Checks

Missing credentials must return `401`. This confirms the SecurityPolicy blocks unauthenticated traffic:

```bash
curl -i "http://$NLB/v1/models"
```

Valid credentials must return `200`. This confirms authentication, routing, and backend reachability:

```bash
curl -i "http://$NLB/v1/models" \
  -H "Authorization: Bearer notforprod"
```

The inference request must return a completion. This validates the full NLB-to-vLLM path:

```bash
curl -i "http://$NLB/v1/chat/completions" \
  -H "Authorization: Bearer notforprod" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/models",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 16
  }'
```

## Fast Failure Triage

```bash
# Read recent events across the application, Envoy, and AI control planes.
# Events expose admission, scheduling, reconciliation, and provisioning failures.
kubectl get events -n "$NS" --sort-by=.lastTimestamp | tail -30
kubectl get events -n "$EG_NS" --sort-by=.lastTimestamp | tail -30
kubectl get events -n "$AI_NS" --sort-by=.lastTimestamp | tail -30

# Inspect each AI routing layer to locate unresolved backend references.
kubectl describe aigatewayroute deepseek-r1-14b -n "$NS"
kubectl describe aiservicebackend deepseek-r1-14b -n "$NS"
kubectl describe backend deepseek-r1-14b -n "$NS"
```