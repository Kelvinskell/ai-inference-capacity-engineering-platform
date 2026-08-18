# ADR 003: S3 Model Artifact Storage

**Status:** Accepted

## Context

The DeepSeek model artifact must remain available when GPU nodes are replaced or new predictor replicas are added. The platform can scale a one-GPU predictor across multiple GPU nodes, so the model distribution design cannot bind all replicas to a single node.

I evaluated three options for model storage and distribution.

### Option 1: EBS-backed PVC

An EBS-backed PersistentVolumeClaim would provide durable block storage for the model. I rejected it as the primary distribution layer because EBS volumes commonly use `ReadWriteOnce`. A single volume cannot be mounted by predictor replicas across multiple nodes, which conflicts with horizontal scaling. Creating one volume per replica would duplicate large model artifacts and create synchronization and lifecycle overhead.

### Option 2: Node-local cache populated by a DaemonSet

A DaemonSet can download the model to local disk on every GPU node, and predictor pods can mount the cached path. I rejected it for this project because every newly provisioned GPU node would need to schedule the DaemonSet and populate the cache before it could serve inference. That adds model-download time to scale-out and makes model availability dependent on each node's local disk. Node-local caching is a useful optimization, but it is not a durable shared artifact source.

### Option 3: S3-backed shared model storage

S3 provides durable, centralized object storage independent of the GPU node lifecycle. The S3 CSI driver exposes the model prefix through a `ReadOnlyMany` PersistentVolume, so predictor replicas on different nodes can read the same artifact. A Kubernetes Job imports a pinned Hugging Face revision into S3 before serving begins.

## Decision

I chose option 3: S3-backed shared model storage with a one-time model uploader Job.

The [uploader Job](../../kubernetes/storage/model-uploader-job.yaml) runs on demand to download the configured Hugging Face snapshots and synchronize them to S3. It is not part of the request-driven scale-out path. The [synchronization script](../../scripts/s3-model-upload/sync_models_to_s3.py) pins each model revision, records SHA-256 hashes as object metadata, skips unchanged files, and writes a completion manifest only after all files upload successfully.

The [S3 Terraform module](../../terraform/modules/s3-model-storage/main.tf) creates a versioned, encrypted, private bucket. The [S3 CSI PersistentVolume](../../kubernetes/serving/kserve/deepseek-r1-14b/persistent-volume.yaml) and [PersistentVolumeClaim](../../kubernetes/serving/kserve/deepseek-r1-14b/persistent-volume-claim.yaml) expose the DeepSeek model with `ReadOnlyMany` access. The [predictor deployment](../../kubernetes/serving/kserve/deepseek-r1-14b/deployment.yaml) mounts that claim read-only at `/models`.

## Rationale

- I separate the artifact lifecycle from the GPU-node lifecycle. Nodes can be created, replaced, or removed without losing the model source.
- I avoid repeated Hugging Face downloads during serving and scale-out. The uploader Job performs ingestion before replicas need the artifact.
- I use a pinned model revision and object hashes to make the served artifact reproducible and to make repeated uploads idempotent.
- I use `ReadOnlyMany` shared access so replicas can scale across nodes without duplicating the model into one EBS volume per replica.
- I keep the platform's model artifact in AWS-owned, encrypted, versioned, non-public storage.

## Consequences

- A new predictor replica can mount the shared model artifact without waiting for a DaemonSet to populate node-local storage.
- The model uploader Job must complete successfully before a newly added model is available to serve.
- S3 CSI access is appropriate for read-only model distribution but is not a general-purpose high-performance filesystem. Model write operations must occur through the uploader workflow, not through predictor pods.
- Node-local caching remains a future optimization if measured model mount or read performance becomes a material scale-out bottleneck. It would complement S3 rather than replace it as the durable source of truth.