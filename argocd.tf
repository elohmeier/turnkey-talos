locals {
  argocd_enabled            = var.argocd_enabled
  argocd_tailscale_hostname = "${var.cluster_name}-argocd"

  argocd_values = {
    # node tolerations for control-plane only clusters
    controller = {
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

      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
    }

    redis = {
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
    }

    server = {
      ingress = {
        enabled = false
      }
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

      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
    }
    repoServer = {
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

      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
    }
    applicationSet = {
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

      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
    }
    configs = {
      params = {
        "server.insecure" = var.tailscale_enabled
      }
    }
  }
}

resource "helm_release" "argocd" {
  count = local.argocd_enabled ? 1 : 0

  name      = "argocd"
  namespace = "argocd"

  repository       = var.argocd_helm_repository
  chart            = var.argocd_helm_chart
  version          = var.argocd_helm_version
  create_namespace = true
  wait             = false

  values = [
    yamlencode(
      merge(
        local.argocd_values,
        var.argocd_helm_values
      )
    )
  ]
}

resource "kubernetes_ingress_v1" "argocd_tailscale" {
  count = var.tailscale_enabled ? 1 : 0

  metadata {
    name      = "argocd-tailscale"
    namespace = "argocd"
  }

  spec {
    ingress_class_name = "tailscale"

    rule {
      host = "${local.argocd_tailscale_hostname}.${var.tailscale_tailnet}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                name = "http"
              }
            }
          }
        }
      }
    }

    tls {
      hosts = ["${local.argocd_tailscale_hostname}.${var.tailscale_tailnet}"]
    }
  }

  depends_on = [
    helm_release.argocd
  ]
}

data "http" "argocd_grafana_dashboard" {
  count = local.argocd_enabled ? 1 : 0

  url = "https://raw.githubusercontent.com/argoproj/argo-cd/refs/heads/master/examples/dashboard.json"
}

resource "kubernetes_config_map_v1" "argocd_grafana_dashboard" {
  count = local.argocd_enabled ? 1 : 0

  metadata {
    name      = "argocd-grafana-dashboard"
    namespace = "argocd"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "argocd-dashboard.json" = data.http.argocd_grafana_dashboard[0].response_body
  }

  depends_on = [
    helm_release.argocd
  ]
}

resource "kubernetes_manifest" "argocd_grafana_dashboard" {
  count = local.argocd_enabled && var.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "argocd-grafana-dashboard"
      namespace = "argocd"
    }
    spec = {
      allowCrossNamespaceImport = true
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      configMapRef = {
        name = "argocd-grafana-dashboard"
        key  = "argocd-dashboard.json"
      }
    }
  }

  depends_on = [
    kubernetes_config_map_v1.argocd_grafana_dashboard
  ]
}
