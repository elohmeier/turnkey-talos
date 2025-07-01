resource "kubernetes_manifest" "cluster_autoscaler_service_monitor" {
  count = var.victoriametrics_enabled ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "cluster-autoscaler"
      namespace = "kube-system"
      labels = {
        "app.kubernetes.io/name"     = "cluster-autoscaler"
        "app.kubernetes.io/instance" = "cluster-autoscaler"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/instance" = "cluster-autoscaler"
          "app.kubernetes.io/name"     = "hetzner-cluster-autoscaler"
        }
      }
      endpoints = [
        {
          port     = "http"
          interval = "30s"
          path     = "/metrics"
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "cluster_autoscaler_grafana_dashboard" {
  count = var.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "cluster-autoscaler"
      namespace = "kube-system"
    }
    spec = {
      allowCrossNamespaceImport = true
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      grafanaCom = {
        id = 12623
      }
    }
  }
}
