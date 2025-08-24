locals {
  pushgateway_enabled                   = var.k8up_enabled && var.victoriametrics_enabled
  pushgateway_namespace                 = "pushgateway"
  pushgateway_tailscale_ingress_enabled = local.pushgateway_enabled && var.tailscale_enabled
  pushgateway_tailscale_hostname        = "${var.cluster_name}-pushgateway"

  pushgateway_values = {
    # Configure node placement for control-plane only clusters
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

    # Enable ServiceMonitor for VMAgent scraping
    serviceMonitor = {
      enabled   = true
      namespace = local.pushgateway_namespace
      additionalLabels = {
        "prometheus-instance" = "vmks-vm-k8s"
      }
    }

    # Configure ingress if Tailscale is enabled
    ingress = {
      enabled   = local.pushgateway_tailscale_ingress_enabled
      className = "tailscale"
      hosts = local.pushgateway_tailscale_ingress_enabled ? [
        "${local.pushgateway_tailscale_hostname}.${var.tailscale_tailnet}"
      ] : []
      paths = [
        {
          path     = "/"
          pathType = "Prefix"
        }
      ]
      tls = local.pushgateway_tailscale_ingress_enabled ? [
        {
          hosts = ["${local.pushgateway_tailscale_hostname}.${var.tailscale_tailnet}"]
        }
      ] : []
    }

    # Configure persistence
    persistentVolume = {
      enabled = false # Push gateway is stateless, metrics are scraped regularly
    }

    # Resources
    resources = {
      limits = {
        cpu    = "200m"
        memory = "128Mi"
      }
      requests = {
        cpu    = "50m"
        memory = "64Mi"
      }
    }
  }
}

resource "kubernetes_namespace_v1" "pushgateway" {
  count = local.pushgateway_enabled ? 1 : 0

  metadata {
    name = local.pushgateway_namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }
}

resource "helm_release" "pushgateway" {
  count = local.pushgateway_enabled ? 1 : 0

  name      = "prometheus-pushgateway"
  namespace = local.pushgateway_namespace

  repository       = var.pushgateway_helm_repository
  chart            = var.pushgateway_helm_chart
  version          = var.pushgateway_helm_version
  create_namespace = false
  wait             = false

  values = [
    yamlencode(
      merge(
        local.pushgateway_values,
        var.pushgateway_helm_values
      )
    )
  ]

  depends_on = [
    kubernetes_namespace_v1.pushgateway,
    helm_release.victoriametrics
  ]
}
