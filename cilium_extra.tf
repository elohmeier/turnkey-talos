data "http" "cilium_ping_nodes_grafana_dashboard" {
  url = "https://raw.githubusercontent.com/deckhouse/deckhouse/refs/heads/main/modules/021-cni-cilium/monitoring/grafana-dashboards/kubernetes-cluster/cilium-ping-nodes.json"
}

resource "kubernetes_manifest" "cilium_ping_nodes_grafana_dashboard" {
  count = var.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "cilium-ping-nodes"
      namespace = "kube-system"
    }
    spec = {
      allowCrossNamespaceImport = true
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      plugins = [{
        name    = "esnet-matrix-panel"
        version = "1.0.10"
      }]
      url = "https://raw.githubusercontent.com/deckhouse/deckhouse/refs/heads/main/modules/021-cni-cilium/monitoring/grafana-dashboards/kubernetes-cluster/cilium-ping-nodes.json"
    }
  }
}

resource "kubernetes_manifest" "cilium_operator_grafana_dashboard" {
  count = var.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "cilium-operator-dashboard"
      namespace = "kube-system"
    }
    spec = {
      allowCrossNamespaceImport = true
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      configMapRef = {
        name = "cilium-operator-dashboard"
        key  = "cilium-operator-dashboard.json"
      }
    }
  }
}

resource "kubernetes_manifest" "cilium_dashboard_grafana_dashboard" {
  count = var.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "cilium-dashboard"
      namespace = "kube-system"
    }
    spec = {
      allowCrossNamespaceImport = true
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      configMapRef = {
        name = "cilium-dashboard"
        key  = "cilium-dashboard.json"
      }
    }
  }
}

resource "kubernetes_manifest" "hubble_dashboard_grafana_dashboard" {
  count = var.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "hubble-dashboard"
      namespace = "kube-system"
    }
    spec = {
      allowCrossNamespaceImport = true
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      configMapRef = {
        name = "hubble-dashboard"
        key  = "hubble-dashboard.json"
      }
    }
  }
}

resource "kubernetes_manifest" "cilium_prometheus_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "cilium-prometheus-rules"
      namespace = "kube-system"
      labels = {
        prometheus = "cilium"
        role       = "alert-rules"
      }
    }
    spec = {
      groups = [
        # based on https://raw.githubusercontent.com/deckhouse/deckhouse/refs/heads/main/modules/021-cni-cilium/monitoring/prometheus-rules/agent.yaml
        {
          name = "cilium.agent"
          rules = [
            {
              alert = "CiliumAgentUnreachableHealthEndpoints"
              expr  = "max by (namespace, pod) (cilium_unreachable_health_endpoints) > 0"
              for   = "5m"
              labels = {
                severity  = "warning"
                component = "cilium-agent"
              }
              annotations = {
                summary     = "Cilium agent {{ $labels.namespace }}/{{ $labels.pod }} can't reach some health endpoints"
                description = "Cilium agent {{ $labels.namespace }}/{{ $labels.pod }} has unreachable health endpoints. Check agent logs: kubectl -n {{ $labels.namespace }} logs {{ $labels.pod }}"
              }
            },
            {
              alert = "CiliumAgentMetricNotFound"
              expr  = "(count by (namespace,pod) (cilium_unreachable_health_endpoints) OR count by (namespace,pod) (cilium_endpoint_state)) != 1"
              for   = "5m"
              labels = {
                severity  = "warning"
                component = "cilium-agent"
              }
              annotations = {
                summary     = "Cilium agent {{ $labels.namespace }}/{{ $labels.pod }} isn't sending expected metrics"
                description = "Cilium agent {{ $labels.namespace }}/{{ $labels.pod }} is missing some expected metrics. Check agent logs: kubectl -n {{ $labels.namespace }} logs {{ $labels.pod }}. Verify agent health: kubectl -n {{ $labels.namespace }} exec -ti {{ $labels.pod }} -- cilium-health status"
              }
            },
            {
              alert = "CiliumAgentEndpointsNotReady"
              expr  = "sum by (namespace, pod) (cilium_endpoint_state{endpoint_state=\"ready\"} / cilium_endpoint_state) < 0.5"
              for   = "5m"
              labels = {
                severity  = "warning"
                component = "cilium-agent"
              }
              annotations = {
                summary     = "Over 50% of endpoints not ready in Cilium agent {{ $labels.namespace }}/{{ $labels.pod }}"
                description = "Cilium agent {{ $labels.namespace }}/{{ $labels.pod }} has over 50% of endpoints in non-ready state. Check agent logs: kubectl -n {{ $labels.namespace }} logs {{ $labels.pod }}"
              }
            },
            {
              alert = "CiliumAgentMapPressureCritical"
              expr  = "sum by (namespace, pod, map_name) (cilium_bpf_map_pressure > 0.9)"
              for   = "5m"
              labels = {
                severity  = "critical"
                component = "cilium-agent"
              }
              annotations = {
                summary     = "eBPF map {{ $labels.map_name }} exceeds 90% utilization in Cilium agent {{ $labels.namespace }}/{{ $labels.pod }}"
                description = "eBPF map {{ $labels.map_name }} in Cilium agent {{ $labels.namespace }}/{{ $labels.pod }} is over 90% utilized. This may impact network functionality."
              }
            },
            {
              alert = "CiliumAgentPolicyImportErrors"
              expr  = "sum by (namespace, pod) (rate(cilium_policy_import_errors_total[2m]) > 0)"
              for   = "5m"
              labels = {
                severity  = "warning"
                component = "cilium-agent"
              }
              annotations = {
                summary     = "Cilium agent {{ $labels.namespace }}/{{ $labels.pod }} has policy import errors"
                description = "Cilium agent {{ $labels.namespace }}/{{ $labels.pod }} is failing to import network policies. Check agent logs: kubectl -n {{ $labels.namespace }} logs {{ $labels.pod }}"
              }
            },
          ]
        }
      ]
    }
  }
}
