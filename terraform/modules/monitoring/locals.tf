# Build Prometheus PVC storage spec with optional StorageClass override.
locals {
  prometheus_storage_spec = {
    volumeClaimTemplate = {
      spec = merge(
        {
          # Use single-node write mode for Prometheus TSDB volume.
          accessModes = ["ReadWriteOnce"]
          resources = {
            requests = {
              storage = var.prometheus_storage_size
            }
          }
        },
        # If storage class is empty, Kubernetes default storage class is used.
        var.prometheus_storage_class == "" ? {} : { storageClassName = var.prometheus_storage_class }
      )
    }
  }
}