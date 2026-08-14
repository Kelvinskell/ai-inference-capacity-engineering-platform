# Deploy kube-prometheus-stack via Helm for cluster observability.
resource "helm_release" "kube_prometheus_stack" {
  count = var.enabled ? 1 : 0

  name             = var.release_name
  repository       = var.repository
  chart            = var.chart
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  # Ensure safer upgrades with rollback on failure.
  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds

  set_sensitive = [
    {
      name  = "grafana.adminPassword"
      value = var.grafana_admin_password
    }
  ]

  values = [
    yamlencode({
      # Install Prometheus Operator CRDs with the chart.
      crds = {
        enabled = true
      }

      # Keep Grafana enabled by default.
      grafana = {
        enabled = true
      }

      prometheus = {
        prometheusSpec = {
          retention   = var.prometheus_retention
          storageSpec = local.prometheus_storage_spec
          # Allow selecting ServiceMonitors and PodMonitors beyond Helm-labeled objects.
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
        }
      }
    })
  ]
  depends_on = [
    kubernetes_storage_class_v1.prometheus
  ]
}

# Install DCGM (Data Center GPU Manager) Exporter
resource "helm_release" "dcgm_exporter" {
  count = var.enabled && var.enable_dcgm_exporter ? 1 : 0

  name             = "dcgm-exporter"
  repository       = "https://nvidia.github.io/dcgm-exporter/helm-charts/"
  chart            = "dcgm-exporter"
  version          = var.dcgm_exporter_chart_version
  namespace        = var.namespace
  create_namespace = false

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds

  values = [
    yamlencode({
      serviceMonitor = {
        enabled = true
        additionalLabels = {
          release = "kube-prometheus-stack"
        }
      }
      nodeSelector = {
        "gpu" = "true"
      }

      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}

# Publish Grafana dashboards as labeled ConfigMaps for the Grafana sidecar.
resource "kubernetes_config_map_v1" "gpu_dashboard" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "gpu-dashboard"
    namespace = var.namespace
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "gpu-dashboard.json" = file("${path.module}/grafana/gpu-dashboard.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_config_map_v1" "latency_dashboard" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "latency-dashboard"
    namespace = var.namespace
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "latency-dashboard.json" = file("${path.module}/grafana/latency-dashboard.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_config_map_v1" "inference_dashboard" {
  count = var.enabled ? 1 : 0

  metadata {
    name      = "inference-dashboard"
    namespace = var.namespace
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "inference-dashboard.json" = file("${path.module}/grafana/inference-dashboard.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}