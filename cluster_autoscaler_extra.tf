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

resource "kubernetes_manifest" "cluster_autoscaler_prometheus_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "cluster-autoscaler-prometheus-rules"
      namespace = "kube-system"
      labels = {
        prometheus = "cluster-autoscaler"
        role       = "alert-rules"
      }
    }
    spec = {
      groups = [
        {
          name = "cluster-autoscaler.rules"
          rules = [
            {
              alert = "ClusterAutoscalerErrors"
              expr  = "increase(cluster_autoscaler_errors_total[5m]) > 0"
              for   = "5m"
              labels = {
                severity  = "warning"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "Cluster Autoscaler is experiencing errors"
                description = "Cluster Autoscaler has reported {{ $value }} errors in the last 5 minutes. Check the autoscaler logs for details."
              }
            },
            {
              alert = "ClusterAutoscalerFailedScaleUps"
              expr  = "increase(cluster_autoscaler_failed_scale_ups_total[10m]) > 0"
              for   = "5m"
              labels = {
                severity  = "warning"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "Cluster Autoscaler failed to scale up nodes"
                description = "Cluster Autoscaler has failed to scale up {{ $value }} times in the last 10 minutes. This may indicate resource constraints or configuration issues."
              }
            },
            {
              alert = "ClusterAutoscalerUnschedulablePods"
              expr  = "cluster_autoscaler_unschedulable_pods_count > 0"
              for   = "10m"
              labels = {
                severity  = "warning"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "Cluster Autoscaler has unschedulable pods"
                description = "Cluster Autoscaler reports {{ $value }} unschedulable pods for more than 10 minutes. This may indicate insufficient cluster capacity or node constraints."
              }
            },
            {
              alert = "ClusterAutoscalerNodesNotReady"
              expr  = "cluster_autoscaler_nodes_count{state=\"notReady\"} > 0"
              for   = "15m"
              labels = {
                severity  = "warning"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "Cluster Autoscaler reports nodes not ready"
                description = "Cluster Autoscaler reports {{ $value }} nodes in notReady state for more than 15 minutes."
              }
            },
            {
              alert = "ClusterAutoscalerMaxNodesReached"
              expr  = "cluster_autoscaler_nodes_count >= cluster_autoscaler_max_nodes_count"
              for   = "5m"
              labels = {
                severity  = "critical"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "Cluster Autoscaler has reached maximum node count"
                description = "Cluster Autoscaler has reached the maximum configured node count ({{ $value }}). No further scaling up is possible."
              }
            },
            {
              alert = "ClusterAutoscalerScaleUpFailureRate"
              expr  = "rate(cluster_autoscaler_failed_scale_ups_total[30m]) / rate(cluster_autoscaler_scale_ups_total[30m]) > 0.5"
              for   = "10m"
              labels = {
                severity  = "critical"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "High cluster autoscaler scale-up failure rate"
                description = "Cluster Autoscaler scale-up failure rate is {{ $value | humanizePercentage }} over the last 30 minutes, indicating persistent scaling issues."
              }
            },
            {
              alert = "ClusterAutoscalerLastActivity"
              expr  = "time() - cluster_autoscaler_last_activity{activity=\"main\"} > 3600"
              for   = "5m"
              labels = {
                severity  = "warning"
                component = "cluster-autoscaler"
              }
              annotations = {
                summary     = "Cluster Autoscaler has been inactive"
                description = "Cluster Autoscaler has not reported any main loop activity for more than 1 hour. This may indicate the autoscaler is not functioning properly."
              }
            }
          ]
        }
      ]
    }
  }
}
