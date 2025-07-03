locals {
  longhorn_backup_s3_endpoint = "${var.location}.your-objectstorage.com"
  longhorn_tailscale_hostname = "${var.cluster_name}-longhorn"
}


resource "kubernetes_ingress_v1" "longhorn_tailscale" {
  metadata {
    name      = "longhorn-tailscale"
    namespace = "longhorn-system"
  }

  spec {
    ingress_class_name = "tailscale"

    tls {
      hosts = ["${local.longhorn_tailscale_hostname}.${var.tailscale_tailnet}"]
    }

    rule {
      host = "${local.longhorn_tailscale_hostname}.${var.tailscale_tailnet}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "longhorn-frontend"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.tailscale
  ]
}

resource "kubernetes_manifest" "longhorn_prometheus_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "longhorn-prometheus-rules"
      namespace = "longhorn-system"
      labels = {
        prometheus = "longhorn"
        role       = "alert-rules"
      }
    }
    spec = {
      groups = [
        {
          name = "longhorn.rules"
          rules = [
            {
              alert = "LonghornVolumeActualSpaceUsedWarning"
              annotations = {
                description = "The actual space used by Longhorn volume {{$labels.volume}} on {{$labels.node}} is at {{$value}}% capacity for more than 5 minutes."
                summary     = "The actual used space of Longhorn volume is over 90% of the capacity."
                link        = "https://${local.longhorn_tailscale_hostname}.${var.tailscale_tailnet}/#/volume/{{$labels.volume}}"
                dashboard   = "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}/d/ozk-lh-mon/longhorn-monitoring?var-volume={{$labels.volume}}"
              }
              expr = "(longhorn_volume_actual_size_bytes / longhorn_volume_capacity_bytes) * 100 > 90"
              for  = "5m"
              labels = {
                issue    = "The actual used space of Longhorn volume {{$labels.volume}} on {{$labels.node}} is high."
                severity = "warning"
              }
            },
            {
              alert = "LonghornVolumeStatusCritical"
              annotations = {
                description = "Longhorn volume {{$labels.volume}} on {{$labels.node}} is Fault for more than 2 minutes."
                summary     = "Longhorn volume {{$labels.volume}} is Fault"
                link        = "https://${local.longhorn_tailscale_hostname}.${var.tailscale_tailnet}/#/volume/{{$labels.volume}}"
                dashboard   = var.victoriametrics_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}/d/ozk-lh-mon/longhorn-monitoring?var-volume={{$labels.volume}}" : ""
              }
              expr = "longhorn_volume_robustness == 3"
              for  = "5m"
              labels = {
                issue    = "Longhorn volume {{$labels.volume}} is Fault."
                severity = "critical"
              }
            },
            {
              alert = "LonghornVolumeStatusWarning"
              annotations = {
                description = "Longhorn volume {{$labels.volume}} on {{$labels.node}} is Degraded for more than 5 minutes."
                summary     = "Longhorn volume {{$labels.volume}} is Degraded"
                link        = "https://${local.longhorn_tailscale_hostname}.${var.tailscale_tailnet}/#/volume/{{$labels.volume}}"
                dashboard   = var.victoriametrics_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}/d/ozk-lh-mon/longhorn-monitoring?var-volume={{$labels.volume}}" : ""
              }
              expr = "longhorn_volume_robustness == 2"
              for  = "5m"
              labels = {
                issue    = "Longhorn volume {{$labels.volume}} is Degraded."
                severity = "warning"
              }
            },
            {
              alert = "LonghornNodeStorageWarning"
              annotations = {
                description = "The used storage of node {{$labels.node}} is at {{$value}}% capacity for more than 5 minutes."
                summary     = "The used storage of node is over 70% of the capacity."
                link        = "https://${local.longhorn_tailscale_hostname}.${var.tailscale_tailnet}/#/node?field=name&value={{$labels.node}}"
                dashboard   = var.victoriametrics_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}/d/ozk-lh-mon/longhorn-monitoring" : ""
              }
              expr = "(longhorn_node_storage_usage_bytes / longhorn_node_storage_capacity_bytes) * 100 > 70"
              for  = "5m"
              labels = {
                issue    = "The used storage of node {{$labels.node}} is high."
                severity = "warning"
              }
            },
            {
              alert = "LonghornDiskStorageWarning"
              annotations = {
                description = "The used storage of disk {{$labels.disk}} on node {{$labels.node}} is at {{$value}}% capacity for more than 5 minutes."
                summary     = "The used storage of disk is over 70% of the capacity."
                link        = "https://${local.longhorn_tailscale_hostname}.${var.tailscale_tailnet}/#/node?field=name&value={{$labels.node}}"
                dashboard   = var.victoriametrics_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}/d/ozk-lh-mon/longhorn-monitoring" : ""
              }
              expr = "(longhorn_disk_usage_bytes / longhorn_disk_capacity_bytes) * 100 > 70"
              for  = "5m"
              labels = {
                issue    = "The used storage of disk {{$labels.disk}} on node {{$labels.node}} is high."
                severity = "warning"
              }
            },
            {
              alert = "LonghornNodeDown"
              annotations = {
                description = "There are {{$value}} Longhorn nodes which have been offline for more than 5 minutes."
                summary     = "Longhorn nodes is offline"
                dashboard   = var.victoriametrics_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}/d/ozk-lh-mon/longhorn-monitoring" : ""
              }
              expr = "(avg(longhorn_node_count_total) or on() vector(0)) - (count(longhorn_node_status{condition=\"ready\"} == 1) or on() vector(0)) > 0"
              for  = "5m"
              labels = {
                issue    = "There are {{$value}} Longhorn nodes are offline"
                severity = "critical"
              }
            },
            {
              alert = "LonghornInstanceManagerCPUUsageWarning"
              annotations = {
                description = "Longhorn instance manager {{$labels.instance_manager}} on {{$labels.node}} has CPU Usage / CPU request is {{$value}}% for more than 5 minutes."
                summary     = "Longhorn instance manager {{$labels.instance_manager}} on {{$labels.node}} has CPU Usage / CPU request is over 300%."
                link        = "https://${local.longhorn_tailscale_hostname}.${var.tailscale_tailnet}/#/node?field=name&value={{$labels.node}}"
                dashboard   = var.victoriametrics_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}/d/ozk-lh-mon/longhorn-monitoring" : ""
              }
              expr = "(longhorn_instance_manager_cpu_usage_millicpu/longhorn_instance_manager_cpu_requests_millicpu) * 100 > 300"
              for  = "5m"
              labels = {
                issue    = "Longhorn instance manager {{$labels.instance_manager}} on {{$labels.node}} consumes 3 times the CPU request."
                severity = "warning"
              }
            },
            {
              alert = "LonghornNodeCPUUsageWarning"
              annotations = {
                description = "Longhorn node {{$labels.node}} has CPU Usage / CPU capacity is {{$value}}% for more than 5 minutes."
                summary     = "Longhorn node {{$labels.node}} experiences high CPU pressure for more than 5m."
                link        = "https://${local.longhorn_tailscale_hostname}.${var.tailscale_tailnet}/#/node?field=name&value={{$labels.node}}"
                dashboard   = var.victoriametrics_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}/d/ozk-lh-mon/longhorn-monitoring" : ""
              }
              expr = "(longhorn_node_cpu_usage_millicpu / longhorn_node_cpu_capacity_millicpu) * 100 > 90"
              for  = "5m"
              labels = {
                issue    = "Longhorn node {{$labels.node}} experiences high CPU pressure."
                severity = "warning"
              }
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_network_policy_v1" "longhorn_allow_victoriametrics" {
  count = var.victoriametrics_enabled ? 1 : 0

  metadata {
    name      = "longhorn-allow-victoriametrics"
    namespace = "longhorn-system"
  }

  spec {
    pod_selector {
      match_labels = {
        app = "longhorn-manager"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "victoriametrics"
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "vmagent"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "9500"
      }
    }
  }
}

resource "kubernetes_secret_v1" "longhorn_backup_secret" {
  metadata {
    name      = "longhorn-backup-secret"
    namespace = "longhorn-system"
  }

  type = "Opaque"

  data = {
    AWS_ACCESS_KEY_ID     = var.s3_admin_access_key
    AWS_SECRET_ACCESS_KEY = var.s3_admin_secret_key
    AWS_ENDPOINTS         = local.longhorn_backup_s3_endpoint
  }
}

data "http" "longhorn_dashboard" {
  url = "https://raw.githubusercontent.com/onzack/grafana-dashboards/b67bd65d6c89ebdc6cfe5b03ac9c75d3d4b616eb/grafana/longhorn/onzack-longhorn-monitoring.json"
}

resource "kubernetes_config_map_v1" "longhorn_grafana_dashboard" {
  metadata {
    name      = "longhorn-dashboard"
    namespace = "longhorn-system"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "longhorn.json" = data.http.longhorn_dashboard.response_body
  }
}

resource "kubernetes_manifest" "longhorn_grafana_dashboard" {
  count = var.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "longhorn-dashboard"
      namespace = "longhorn-system"
    }
    spec = {
      allowCrossNamespaceImport = true
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      configMapRef = {
        name = "longhorn-dashboard"
        key  = "longhorn.json"
      }
    }
  }

  depends_on = [
    kubernetes_config_map_v1.longhorn_grafana_dashboard
  ]
}
