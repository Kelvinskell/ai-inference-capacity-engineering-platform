resource "helm_release" "open_webui" {
  count = var.enabled ? 1 : 0

  name             = "open-webui"
  repository       = "https://helm.openwebui.com/"
  chart            = "open-webui"
  version          = var.open_webui_chart_version
  namespace        = "open-webui"
  create_namespace = true

  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds

  values = [
    yamlencode({
      ollama = {
        enabled = false
      }
      pipelines = {
        enabled = false
      }
      tika = {
        enabled = false
      }
      terminals = {
        enabled = false
      }
      websocket = {
        enabled = false
        manager = ""
        redis = {
          enabled = false
        }
      }

      replicaCount = 1

      persistence = {
        enabled      = true
        storageClass = var.open_webui_storage_class
        size         = var.open_webui_storage_size
        accessModes  = ["ReadWriteOnce"]
      }

      service = {
        type          = "ClusterIP"
        port          = 80
        containerPort = 8080
      }

      enableOpenaiApi  = true
      openaiBaseApiUrl = var.openai_base_api_url
      openaiApiKey     = var.development_secret

      extraEnvVars = [
        {
          name  = "WEBUI_SECRET_KEY"
          value = var.development_secret
        },
        {
          name  = "ENABLE_OLLAMA_API"
          value = "false"
        },
        {
          name = "OPENAI_API_CONFIGS"
          value = jsonencode({
            "0" = {
              enable    = true
              auth_type = "bearer"
              model_ids = ["/models"]
            }
          })
        },
      ]

      resources = {
        requests = {
          cpu    = "250m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
      }

      startupProbe = {
        httpGet = {
          path = "/health"
          port = "http"
        }
        periodSeconds    = 5
        failureThreshold = 30
      }
      readinessProbe = {
        httpGet = {
          path = "/health/db"
          port = "http"
        }
        periodSeconds    = 10
        failureThreshold = 3
      }
      livenessProbe = {
        httpGet = {
          path = "/health"
          port = "http"
        }
        periodSeconds    = 10
        failureThreshold = 3
      }
    })
  ]
}