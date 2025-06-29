locals {
  kubetail_enabled            = var.kubetail_enabled
  kubetail_tailscale_hostname = "${var.cluster_name}-kubetail"

  kubetail_values = {
    kubetail = {
      allowedNamespaces = var.kubetail_allowed_namespaces

      dashboard = {
        enabled  = true
        authMode = "auto"

        podTemplate = {
          nodeSelector = var.worker_count == 0 ? {
            "node-role.kubernetes.io/control-plane" = ""
          } : {}

          tolerations = var.worker_count == 0 ? [
            {
              key      = "node-role.kubernetes.io/control-plane"
              operator = "Exists"
              effect   = "NoSchedule"
            }
          ] : []
        }
      }

      clusterAPI = {
        enabled = true

        podTemplate = {
          nodeSelector = var.worker_count == 0 ? {
            "node-role.kubernetes.io/control-plane" = ""
          } : {}

          tolerations = var.worker_count == 0 ? [
            {
              key      = "node-role.kubernetes.io/control-plane"
              operator = "Exists"
              effect   = "NoSchedule"
            }
          ] : []
        }
      }

      clusterAgent = {
        enabled = true
      }
    }
  }
}

resource "kubernetes_namespace_v1" "kubetail" {
  count = var.kubetail_enabled ? 1 : 0

  metadata {
    name = "kubetail"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "kubetail" {
  count = var.kubetail_enabled ? 1 : 0

  name      = "kubetail"
  namespace = "kubetail"

  repository       = var.kubetail_helm_repository
  chart            = var.kubetail_helm_chart
  version          = var.kubetail_helm_version
  create_namespace = false
  wait             = false

  values = [
    yamlencode(
      merge(
        local.kubetail_values,
        var.kubetail_helm_values
      )
    )
  ]

  depends_on = [
    kubernetes_namespace_v1.kubetail
  ]
}

resource "kubernetes_ingress_v1" "kubetail_tailscale" {
  count = var.kubetail_enabled && var.tailscale_enabled ? 1 : 0

  metadata {
    name      = "kubetail-tailscale"
    namespace = "kubetail"
  }

  spec {
    ingress_class_name = "tailscale"

    tls {
      hosts = ["${local.kubetail_tailscale_hostname}.${var.tailscale_tailnet}"]
    }

    rule {
      host = "${local.kubetail_tailscale_hostname}.${var.tailscale_tailnet}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kubetail-dashboard"
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.kubetail,
    helm_release.tailscale
  ]
}
