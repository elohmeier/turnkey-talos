locals {
  k8up_enabled = var.k8up_enabled

  k8up_values = {
    # node tolerations for control-plane only clusters
    tolerations = var.worker_count == 0 ? [
      {
        key      = "node-role.kubernetes.io/control-plane"
        operator = "Exists"
        effect   = "NoSchedule"
      }
    ] : []

    nodeSelector = var.worker_count == 0 ? {
      "node-role.kubernetes.io/control-plane" = ""
    } : {}

    k8up = {
      skipWithoutAnnotation = true
    }

    # Metrics configuration
    metrics = {
      serviceMonitor = {
        enabled = var.victoriametrics_enabled
      }

      prometheusRule = {
        enabled = var.victoriametrics_enabled
      }

      grafanaDashboard = {
        enabled = var.grafana_enabled
        additionalLabels = {
          grafana_dashboard = "1"
        }
      }
    }
  }
}

# Deploy k8up operator
resource "helm_release" "k8up" {
  count = local.k8up_enabled ? 1 : 0

  name      = "k8up"
  namespace = "k8up-system"

  repository       = var.k8up_helm_repository
  chart            = var.k8up_helm_chart
  version          = var.k8up_helm_version
  create_namespace = true
  wait             = false

  values = [
    yamlencode(
      merge(
        local.k8up_values,
        var.k8up_helm_values
      )
    )
  ]
}

resource "kubernetes_manifest" "k8up_grafana_dashboard" {
  count = local.k8up_enabled && var.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "k8up-grafana-dashboard"
      namespace = "k8up-system"
    }
    spec = {
      allowCrossNamespaceImport = true
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      configMapRef = {
        name = "k8up-grafana-dashboard"
        key  = "grafana-dashboard-k8up.json"
      }
    }
  }

  depends_on = [helm_release.k8up]
}
