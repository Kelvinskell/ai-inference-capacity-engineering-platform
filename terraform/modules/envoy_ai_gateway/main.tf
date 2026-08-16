# Install Envoy Gateway with the Gateway API and Envoy Gateway CRDs.
resource "helm_release" "envoy_gateway" {
  count = var.enabled ? 1 : 0

  name             = var.envoy_gateway_release_name
  repository       = var.oci_repository
  chart            = var.envoy_gateway_chart
  version          = var.envoy_gateway_chart_version
  namespace        = var.envoy_gateway_namespace
  create_namespace = true

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds

  values = [
    yamlencode({
      config = {
        envoyGateway = {
          extensionApis = {
            enableBackend = true
          }
        }
      }
    })
  ]
}

# Install Envoy AI Gateway CRDs before starting its controller.
resource "helm_release" "envoy_ai_gateway_crds" {
  count = var.enabled ? 1 : 0

  name             = var.envoy_ai_gateway_crds_release_name
  repository       = var.oci_repository
  chart            = var.envoy_ai_gateway_crds_chart
  version          = var.envoy_ai_gateway_chart_version
  namespace        = var.envoy_ai_gateway_namespace
  create_namespace = true

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds

  depends_on = [helm_release.envoy_gateway]
}

# Install the Envoy AI Gateway controller after both sets of CRDs are available.
resource "helm_release" "envoy_ai_gateway" {
  count = var.enabled ? 1 : 0

  name             = var.envoy_ai_gateway_release_name
  repository       = var.oci_repository
  chart            = var.envoy_ai_gateway_chart
  version          = var.envoy_ai_gateway_chart_version
  namespace        = var.envoy_ai_gateway_namespace
  create_namespace = false

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds

  depends_on = [helm_release.envoy_ai_gateway_crds]
}
