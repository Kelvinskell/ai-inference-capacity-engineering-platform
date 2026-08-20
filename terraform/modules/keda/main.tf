resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.16.1"
  namespace        = "keda"
  create_namespace = true
  timeout          = 900

  set = [
    {
    name  = "crds.install"
    value = "true"
  }
  ]
}