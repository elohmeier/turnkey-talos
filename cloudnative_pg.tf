locals {
  cloudnative_pg_values = {
    replicaCount = var.control_plane_count > 1 ? 2 : 1
    podDisruptionBudget = {
      enabled      = var.control_plane_count > 1
      minAvailable = var.control_plane_count > 1 ? 1 : 0
    }
    topologySpreadConstraints = [
      {
        topologyKey       = "kubernetes.io/hostname"
        maxSkew           = 1
        whenUnsatisfiable = var.control_plane_count > 2 ? "DoNotSchedule" : "ScheduleAnyway"
        labelSelector = {
          matchLabels = {
            "app.kubernetes.io/instance" = "cloudnative-pg"
            "app.kubernetes.io/name"     = "cloudnative-pg"
          }
        }
      }
    ]
    nodeSelector = { "node-role.kubernetes.io/control-plane" : "" }
    tolerations = [
      {
        key      = "node-role.kubernetes.io/control-plane"
        effect   = "NoSchedule"
        operator = "Exists"
      }
    ]
    monitoring = {
      podMonitorEnabled = true
    }
  }
}

resource "helm_release" "cloudnative_pg" {
  count = var.cloudnative_pg_enabled ? 1 : 0

  name      = "cnpg"
  namespace = "cnpg-system"

  repository       = var.cloudnative_pg_helm_repository
  chart            = var.cloudnative_pg_helm_chart
  version          = var.cloudnative_pg_helm_version
  create_namespace = true

  values = [
    yamlencode(
      merge(
        local.cloudnative_pg_values,
        var.cloudnative_pg_helm_values
      )
    )
  ]
}

resource "helm_release" "cloudnative_pg_grafana_dashboard" {
  count = var.cloudnative_pg_enabled ? 1 : 0

  name      = "cnpg-grafana-dashboard"
  namespace = "cnpg-system"

  repository       = var.cloudnative_pg_grafana_dashboard_helm_repository
  chart            = var.cloudnative_pg_grafana_dashboard_helm_chart
  version          = var.cloudnative_pg_grafana_dashboard_helm_version
  create_namespace = false

  values = [
    yamlencode(
      merge(
        {
          grafanaDashboard = {
            namespace = "cnpg-system"
            labels = {
              grafana_dashboard = "1"
            }
          }
        },
        var.cloudnative_pg_grafana_dashboard_helm_values
      )
    )
  ]

  depends_on = [helm_release.cloudnative_pg]
}

resource "kubernetes_manifest" "cloudnative_pg_grafana_dashboard" {
  count = var.cloudnative_pg_enabled && var.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "cnpg-grafana-dashboard"
      namespace = "cnpg-system"
    }
    spec = {
      allowCrossNamespaceImport = true
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      configMapRef = {
        name = "cnpg-grafana-dashboard"
        key  = "cnp.json"
      }
    }
  }

  depends_on = [helm_release.cloudnative_pg_grafana_dashboard]
}
