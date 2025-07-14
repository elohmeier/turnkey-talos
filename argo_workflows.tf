locals {
  argo_workflows_namespace            = "argo-workflows"
  argo_workflows_tailscale_hostname   = "${var.cluster_name}-argo-workflows"
  argo_workflows_artifact_s3_endpoint = "${var.location}.your-objectstorage.com"

  argo_workflows_artifact_s3_bucket_name = "${var.cluster_name}-argo-workflows-artifacts"

  # Calculate total node count for HA decisions
  argo_workflows_total_nodes = var.worker_count > 0 ? var.worker_count : var.control_plane_count
  argo_workflows_ha_enabled  = local.argo_workflows_total_nodes > 1

  # Node placement configuration
  argo_workflows_node_placement = {
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

  # HA configuration for server
  argo_workflows_server_ha = {
    autoscaling = {
      enabled     = local.argo_workflows_ha_enabled
      minReplicas = 2
    }
    pdb = {
      enabled      = local.argo_workflows_ha_enabled
      minAvailable = 1
    }
  }

  # HA configuration for controller
  argo_workflows_controller_ha = {
    replicas = local.argo_workflows_ha_enabled ? 2 : 1
    pdb = {
      enabled      = local.argo_workflows_ha_enabled
      minAvailable = 1
    }
  }

  # Monitoring configuration
  argo_workflows_monitoring = {
    metricsConfig = {
      enabled = true
    }
    # telemetryConfig = {
    #   enabled = true
    # }
    serviceMonitor = {
      enabled = true
    }
  }

  argo_workflows_values = {
    server = merge(
      {
        enabled = true
        ingress = {
          enabled = false
        }
      },
      local.argo_workflows_node_placement,
      local.argo_workflows_server_ha
    )
    controller = merge(
      {
        workflowNamespaces = var.argo_workflows_managed_namespaces
        links = [
          {
            name  = "Workflow Logs"
            scope = "workflow"
            url   = "https://${local.victorialogs_tailscale_hostname}.${var.tailscale_tailnet}/select/vmui/?#/?query=kubernetes.pod_namespace%3A+%22$${metadata.namespace}%22+AND+kubernetes.labels.workflows_argoproj_io%2Fworkflow%3A+%22$${metadata.name}%22&g0.range_input=1h&limit=1000"
          },
          {
            name  = "Pod Logs"
            scope = "pod"
            url   = "https://${local.victorialogs_tailscale_hostname}.${var.tailscale_tailnet}/select/vmui/?#/?query=kubernetes.pod_namespace%3A+%22$${metadata.namespace}%22+AND+kubernetes.pod_name%3A+%22$${metadata.name}%22&g0.range_input=1h&limit=1000"
          },
          {
            name  = "Pod Logs"
            scope = "pod-logs"
            url   = "https://${local.victorialogs_tailscale_hostname}.${var.tailscale_tailnet}/select/vmui/?#/?query=kubernetes.pod_namespace%3A+%22$${metadata.namespace}%22+AND+kubernetes.pod_name%3A+%22$${metadata.name}%22&g0.range_input=1h&limit=1000"
          },
          {
            name  = "Pod Dashboard"
            scope = "pod"
            url   = "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}/d/k8s_views_pods/kubernetes-views-pods?var-namespace=$${metadata.namespace}&var-pod=$${metadata.name}"
          }
        ]
      },
      local.argo_workflows_node_placement,
      local.argo_workflows_monitoring,
      local.argo_workflows_controller_ha
    )
    artifactRepository = {
      archiveLogs = true
      s3 = {
        bucket   = local.argo_workflows_artifact_s3_bucket_name
        endpoint = local.argo_workflows_artifact_s3_endpoint
        region   = var.location
        insecure = false
        accessKeySecret = {
          name = "argo-workflows-s3-creds"
          key  = "accessKey"
        }
        secretKeySecret = {
          name = "argo-workflows-s3-creds"
          key  = "secretKey"
        }
      }
    }
  }
}

resource "kubernetes_namespace_v1" "argo_workflows" {
  count = var.argo_workflows_enabled ? 1 : 0

  metadata {
    name = local.argo_workflows_namespace
  }
}

resource "kubernetes_namespace_v1" "argo_workflows_managed" {
  for_each = var.argo_workflows_enabled ? toset(var.argo_workflows_managed_namespaces) : toset([])

  metadata {
    name = each.key
  }
}

resource "kubernetes_secret_v1" "argo_workflows_s3_creds" {
  count = var.argo_workflows_enabled ? 1 : 0

  metadata {
    name      = "argo-workflows-s3-creds"
    namespace = local.argo_workflows_namespace
  }

  data = {
    accessKey = var.s3_admin_access_key
    secretKey = var.s3_admin_secret_key
  }

  depends_on = [
    kubernetes_namespace_v1.argo_workflows
  ]
}

resource "kubernetes_secret_v1" "argo_workflows_s3_creds_managed" {
  for_each = var.argo_workflows_enabled ? toset(var.argo_workflows_managed_namespaces) : toset([])

  metadata {
    name      = "argo-workflows-s3-creds"
    namespace = each.key
  }

  data = {
    accessKey = var.s3_admin_access_key
    secretKey = var.s3_admin_secret_key
  }

  depends_on = [
    kubernetes_namespace_v1.argo_workflows_managed
  ]
}

resource "helm_release" "argo_workflows" {
  count = var.argo_workflows_enabled ? 1 : 0

  name      = "argo-workflows"
  namespace = local.argo_workflows_namespace

  repository       = var.argo_workflows_helm_repository
  chart            = var.argo_workflows_helm_chart
  version          = var.argo_workflows_helm_version
  create_namespace = false
  wait             = false

  values = [
    yamlencode(
      merge(
        local.argo_workflows_values,
        var.argo_workflows_helm_values
      )
    )
  ]

  depends_on = [
    kubernetes_namespace_v1.argo_workflows,
    kubernetes_namespace_v1.argo_workflows_managed,
    kubernetes_secret_v1.argo_workflows_s3_creds
  ]
}

resource "kubernetes_ingress_v1" "argo_workflows_tailscale" {
  count = var.argo_workflows_enabled && var.tailscale_enabled ? 1 : 0

  metadata {
    name      = "argo-workflows-tailscale"
    namespace = local.argo_workflows_namespace
  }

  spec {
    ingress_class_name = "tailscale"

    rule {
      host = "${local.argo_workflows_tailscale_hostname}.${var.tailscale_tailnet}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argo-workflows-server"
              port {
                number = 2746
              }
            }
          }
        }
      }
    }

    tls {
      hosts = ["${local.argo_workflows_tailscale_hostname}.${var.tailscale_tailnet}"]
    }
  }

  depends_on = [
    kubernetes_namespace_v1.argo_workflows,
  ]
}

data "http" "argo_workflows_grafana_dashboard" {
  count = var.argo_workflows_enabled ? 1 : 0

  url = "https://raw.githubusercontent.com/argoproj/argo-workflows/refs/heads/main/examples/grafana-dashboard.json"
}

resource "kubernetes_config_map_v1" "argo_workflows_grafana_dashboard" {
  count = var.argo_workflows_enabled ? 1 : 0

  metadata {
    name      = "argo-workflows-grafana-dashboard"
    namespace = local.argo_workflows_namespace
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "argo-workflows-dashboard.json" = data.http.argo_workflows_grafana_dashboard[0].response_body
  }

  depends_on = [
    helm_release.argo_workflows
  ]
}

resource "kubernetes_manifest" "argo_workflows_grafana_dashboard" {
  count = var.argo_workflows_enabled && var.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "argo-workflows-grafana-dashboard"
      namespace = local.argo_workflows_namespace
    }
    spec = {
      allowCrossNamespaceImport = true
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      configMapRef = {
        name = "argo-workflows-grafana-dashboard"
        key  = "argo-workflows-dashboard.json"
      }
    }
  }

  depends_on = [
    kubernetes_config_map_v1.argo_workflows_grafana_dashboard
  ]
}

# Auto-create S3 bucket for Argo Workflows artifacts when enabled
resource "minio_s3_bucket" "argo_workflows_artifacts" {
  count = var.argo_workflows_enabled ? 1 : 0

  bucket         = "${var.cluster_name}-argo-workflows-artifacts"
  acl            = "private"
  object_locking = false
}

resource "minio_ilm_policy" "argo_workflows_artifacts" {
  count = var.argo_workflows_enabled ? 1 : 0

  bucket = minio_s3_bucket.argo_workflows_artifacts[0].bucket

  rule {
    id         = "expire-30d"
    status     = "Enabled"
    expiration = "30d"
  }
}
