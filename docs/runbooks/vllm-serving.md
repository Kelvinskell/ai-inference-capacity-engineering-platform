# Runbook: DeepSeek R1 14B AWQ KServe vLLM Validation

## Purpose

This runbook validates the DeepSeek R1 14B AWQ serving workload deployed by KServe in `RawDeployment` mode.

```text
KServe InferenceService
-> KServe predictor Deployment and Service
-> vLLM OpenAI-compatible API
-> EKS Auto Mode GPU node
-> Mountpoint S3 CSI volume
-> S3 model prefix
```

The Kubernetes pipeline applies the serving manifests in:

```text
kubernetes/serving/kserve/deepseek-r1-14b/
```

This is a Phase 1 direct-to-predictor validation path. Envoy AI Gateway is introduced later as the platform entry point.

## Related Manifests

- `kubernetes/serving/kserve/deepseek-r1-14b/sa.yaml`
- `kubernetes/serving/kserve/deepseek-r1-14b/persistent-volume.yaml`
- `kubernetes/serving/kserve/deepseek-r1-14b/persistent-volume-claim.yaml`
- `kubernetes/serving/kserve/deepseek-r1-14b/deployment.yaml`
- `kubernetes/serving/kserve/deepseek-r1-14b/service-monitor.yaml`
- `kubernetes/serving/kserve/deepseek-r1-14b/virtual-service.yaml`

## Serving Configuration

| Setting | Value |
|---|---|
| InferenceService | `deepseek-r1-14b` |
| Namespace | `llm-serving` |
| KServe mode | `RawDeployment` |
| vLLM image | `vllm/vllm-openai:v0.25.1` |
| Model filesystem path | `/models` |
| S3 bucket | `ai-inference-models-dev-538578370232` |
| S3 model prefix | `models/deepseek-14b-awq` |
| PVC | `deepseek-r1-14b` |
| Predictor Service | `deepseek-r1-14b-predictor` |
| Container port | `8000` |
| Predictor Service port | `80` |
| GPU request | `nvidia.com/gpu: "1"` |
| GPU selector | `gpu: "true"` |
| GPU memory utilization | `0.90` |
| Maximum context length | `15000` tokens |
| Maximum concurrent sequences | `16` |

The S3 CSI driver authenticates through its driver-level IAM role. The `deepseek-r1-14b` ServiceAccount does not need its own S3 role for this read-only mount.

## Prerequisites

- `kubectl` context points to the target EKS cluster.
- Namespace `llm-serving` exists.
- KServe, Istio, and Prometheus are deployed.
- The Mountpoint S3 CSI add-on is installed.
- The S3 model uploader completed successfully.
- The S3 bucket contains `models/deepseek-14b-awq/_MANIFEST.json`.
- A GPU NodePool accepts `gpu: "true"` Pods and their `nvidia.com/gpu` toleration.

## Step 1: Apply and Verify Storage

Apply the complete DeepSeek serving directory:

```sh
kubectl apply -f kubernetes/serving/kserve/deepseek-r1-14b/
```

Confirm the static S3 volume binds:

```sh
kubectl get pv deepseek-r1-14b
kubectl get pvc deepseek-r1-14b -n llm-serving
```

Expected PVC state:

```text
STATUS   VOLUME            CAPACITY   ACCESS MODES
Bound    deepseek-r1-14b   1Gi        ROX
```

The `1Gi` capacity is a Kubernetes-required placeholder. It does not limit S3 model size or reserve S3 storage.

## Step 2: Verify the InferenceService

```sh
kubectl get isvc deepseek-r1-14b -n llm-serving
kubectl describe isvc deepseek-r1-14b -n llm-serving
kubectl get deploy,pods,svc -n llm-serving -o wide
```

KServe creates these names:

```text
Deployment: deepseek-r1-14b-predictor
Service:    deepseek-r1-14b-predictor
Pod:        deepseek-r1-14b-predictor-<replicaset-hash>-<pod-id>
```

Watch rollout progress:

```sh
kubectl rollout status deployment/deepseek-r1-14b-predictor -n llm-serving
```

## Step 3: Verify GPU Provisioning

The predictor requests one GPU. If no GPU node exists, EKS Auto Mode provisions a compatible node from the GPU NodePools.

```sh
kubectl get nodes -L gpu,capacity-tier,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
kubectl get nodeclaims
kubectl get pods -n llm-serving -o wide
```

Verify allocatable GPU capacity on the predictor node:

```sh
kubectl describe node <gpu-node-name> | rg -A8 'Allocatable|nvidia.com/gpu'
```

EKS Auto Mode manages the NVIDIA driver and device plugin when a GPU node is provisioned. The node should advertise `nvidia.com/gpu: 1`.

## Step 4: Follow vLLM Startup

Get the current predictor Pod name:

```sh
POD="$(kubectl get pods -n llm-serving \
  -l serving.kserve.io/inferenceservice=deepseek-r1-14b \
  -o jsonpath='{.items[0].metadata.name}')"

printf '%s\n' "$POD"
```

Stream logs:

```sh
kubectl logs -n llm-serving -f "$POD"
```

Expected phases:

```text
Resolved architecture: Qwen2ForCausalLM
Loading model from scratch
Loading safetensors checkpoint shards
Model loading took ...
Available KV cache memory: ...
```

The model is read through a FUSE S3 mount. Cold startup includes S3 reads, loading weights to GPU, vLLM compilation, and KV-cache allocation. The startup probe permits up to 15 minutes for this work. A `Running` Pod is not ready until it reports `1/1`:

```sh
kubectl get pods -n llm-serving -w
```

## Step 5: Troubleshoot Startup Failure

```sh
kubectl describe pod -n llm-serving "$POD"
kubectl logs -n llm-serving "$POD"
kubectl logs -n llm-serving "$POD" --previous
```

### Symptom: liveness restarts vLLM during loading

Cause: vLLM has not opened port `8000` before liveness begins. The deployment requires its `startupProbe`; Kubernetes does not run readiness or liveness probes until startup succeeds.

### Symptom: insufficient KV-cache memory

Cause: the model default context length is `131072`, which does not fit alongside the 14B AWQ model on one 24 GiB A10G.

Use the project baseline:

```yaml
- --max-model-len
- "15000"
```

The context budget is:

```text
system prompt + retained conversation history + current message + generated response <= 15000 tokens
```

### Symptom: `model not found`

This deployment does not configure `--served-model-name`. Query the available identifier instead of guessing:

```sh
curl -s http://127.0.0.1:8000/v1/models | jq
```

Use the returned `data[0].id`; with the current positional model path, it is expected to be `/models`.

## Step 6: Port-Forward and Test the Predictor

The KServe-generated predictor Service uses port `80` and forwards to the vLLM container on `8000`.

```sh
kubectl port-forward \
  -n llm-serving \
  svc/deepseek-r1-14b-predictor \
  8000:80
```

In another terminal, check health and discover the model ID:

```sh
curl -i http://127.0.0.1:8000/health
MODEL_ID="$(curl -s http://127.0.0.1:8000/v1/models | jq -r '.data[0].id')"
printf '%s\n' "$MODEL_ID"
```

Send a minimal OpenAI-compatible request:

```sh
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"${MODEL_ID}\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"A 14B AWQ model runs on one A10G with a 15,000-token context limit. Given 20 requests per minute, 3,000 prompt tokens, and 500 output tokens per request, identify the first two capacity bottlenecks and propose one measurable alert for each.\"}
    ],
    \"max_tokens\": 128,
    \"temperature\": 0.2
  }" | jq
```

Validate streaming:

```sh
curl -N http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"${MODEL_ID}\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"During a traffic spike, p95 time-to-first-token rises from 0.8 to 6 seconds while GPU utilization stays below 55 percent and GPU memory remains near its idle level. State the most likely failure modes to investigate first and the telemetry that would distinguish them.\"}
    ],
    \"max_tokens\": 1200,
    \"temperature\": 0.2,
    \"stream\": true
  }"
```

Useful response fields are `choices[0].message.content`, `choices[0].finish_reason`, and the `usage` token counts.

## Step 7: Verify Prometheus Scraping

```sh
kubectl get servicemonitor deepseek-r1-14b -n llm-serving -o yaml
kubectl get svc deepseek-r1-14b-predictor -n llm-serving --show-labels
kubectl get endpoints deepseek-r1-14b-predictor -n llm-serving
```

Port-forward Prometheus:

```sh
kubectl port-forward \
  -n monitoring \
  svc/kube-prometheus-stack-prometheus \
  9090:9090
```

Confirm the target is `UP`, then use initial GPU queries:

```promql
DCGM_FI_DEV_GPU_UTIL{exported_namespace="llm-serving"}
```

```promql
avg_over_time(DCGM_FI_DEV_GPU_UTIL{exported_namespace="llm-serving"}[5m])
```

```promql
DCGM_FI_DEV_FB_USED{exported_namespace="llm-serving"}
```

GPU framebuffer usage remains high at idle because vLLM retains model weights and KV-cache blocks. GPU utilization rises during prefill and token generation.


## Cleanup

```sh
kubectl delete -f kubernetes/serving/kserve/deepseek-r1-14b/
```

The PV uses `Retain`, so deleting the claim does not delete the S3 bucket or model artifacts.
