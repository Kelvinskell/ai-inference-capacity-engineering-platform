# Fetch upstream manifests
data "http" "knative_serving_crds" {
  url = "https://github.com/knative/serving/releases/download/${var.knative_serving_version}/serving-crds.yaml"
}

data "http" "knative_serving_core" {
  url = "https://github.com/knative/serving/releases/download/${var.knative_serving_version}/serving-core.yaml"
}

data "http" "knative_net_istio" {
  url = "https://github.com/knative-extensions/net-istio/releases/download/${var.knative_net_istio_version}/net-istio.yaml"
}

data "http" "kserve_all" {
  url = "https://github.com/kserve/kserve/releases/download/${var.kserve_version}/kserve.yaml"
}


# Cert manager
resource "helm_release" "cert_manager" {
  name             = var.cert_manager_release_name
  repository       = var.cert_manager_repository
  chart            = var.cert_manager_chart
  version          = var.cert_manager_chart_version
  namespace        = var.cert_manager_namespace
  create_namespace = true

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds

  set = [
  {
    name  = "crds.enabled"
    value = "true"
  }
]
}

# istio base
resource "helm_release" "istio_base" {
  name             = var.istio_base_release_name
  repository       = var.istio_repository
  chart            = "base"
  version          = var.istio_chart_version
  namespace        = var.istio_namespace
  create_namespace = true

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds
}

# Istio daemon
resource "helm_release" "istiod" {
  name             = var.istiod_release_name
  repository       = var.istio_repository
  chart            = "istiod"
  version          = var.istio_chart_version
  namespace        = var.istio_namespace
  create_namespace = true

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds

  depends_on = [helm_release.istio_base]
}

# Istio Ingress
resource "helm_release" "istio_ingressgateway" {
  name             = var.istio_ingressgateway_release_name
  repository       = var.istio_repository
  chart            = "gateway"
  version          = var.istio_chart_version
  namespace        = var.istio_namespace
  create_namespace = true

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds

  depends_on = [helm_release.istiod]
}

# Apply Knative CRDs
resource "kubectl_manifest" "knative_serving_crds" {
  for_each = local.knative_serving_crds_manifest_map

  # Work around kubectl provider read-after-apply flakiness for CRDs.
  apply_only       = true
  wait_for_rollout = false
  yaml_body        = each.value
  depends_on       = [helm_release.istio_ingressgateway]
}

# Create knative-serving namespace before namespaced core prerequisites.
resource "kubectl_manifest" "knative_serving_core_namespace" {
  for_each  = local.knative_serving_core_namespace_manifest_map
  yaml_body = each.value

  depends_on = [kubectl_manifest.knative_serving_crds]
}

# Apply prerequisite Knative objects first.
resource "kubectl_manifest" "knative_serving_core_prereq" {
  for_each  = local.knative_serving_core_prereq_manifest_map
  yaml_body = each.value

  depends_on = [kubectl_manifest.knative_serving_core_namespace]
}

# Apply Knative runtime resources after prerequisites are in place.
resource "kubectl_manifest" "knative_serving_core_runtime" {
  for_each  = local.knative_serving_core_runtime_manifest_map
  yaml_body = each.value

  depends_on = [kubectl_manifest.knative_serving_core_prereq]
}

# Knative webhook may be created during bootstrap; give it time to become ready.
resource "time_sleep" "wait_knative_webhook" {
  create_duration = "60s"

  depends_on = [kubectl_manifest.knative_serving_core_runtime]
}

# Apply Knative internal networking resources after webhook should have endpoints.
resource "kubectl_manifest" "knative_serving_core_webhook" {
  for_each  = local.knative_serving_core_webhook_manifest_map
  yaml_body = each.value

  depends_on = [time_sleep.wait_knative_webhook]
}


# Apply net-istio
resource "kubectl_manifest" "knative_net_istio" {
  for_each  = local.knative_net_istio_manifest_map
  yaml_body = each.value

  depends_on = [kubectl_manifest.knative_serving_core_webhook]
}

# kubectl patch command
resource "kubectl_manifest" "knative_config_network" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "config-network"
      namespace = "knative-serving"
    }
    data = {
      "ingress-class" = var.knative_ingress_class
    }
  })

  depends_on = [kubectl_manifest.knative_net_istio]
}

resource "kubectl_manifest" "kserve_crds" {
  for_each = local.kserve_crd_manifest_map
  # Work around kubectl provider read-after-apply flakiness for CRDs.
  apply_only        = true
  wait_for_rollout  = false
  server_side_apply = true
  force_conflicts   = true
  yaml_body         = each.value

  depends_on = [kubectl_manifest.knative_config_network]
}

# Give apiserver time to establish CRDs before non-CRD objects
resource "time_sleep" "wait_kserve_crds" {
  create_duration = "90s"

  depends_on = [kubectl_manifest.kserve_crds]
}

# Create kserve namespace explicitly before applying other KServe namespaced resources.
resource "kubectl_manifest" "kserve_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "kserve"
    }
  })

  depends_on = [time_sleep.wait_kserve_crds]
}

resource "kubectl_manifest" "kserve_resources" {
  for_each  = local.kserve_non_crd_manifest_map
  yaml_body = each.value

  depends_on = [kubectl_manifest.kserve_namespace]
}