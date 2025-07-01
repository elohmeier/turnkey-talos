locals {
  victoriametrics_enabled                         = var.victoriametrics_enabled
  victoriametrics_tailscale_ingress_enabled       = var.victoriametrics_enabled && var.tailscale_enabled
  victoriametrics_tailscale_hostname              = "${var.cluster_name}-victoriametrics"
  victoriametrics_vmalert_tailscale_hostname      = "${var.cluster_name}-vmalert"
  victoriametrics_vmagent_tailscale_hostname      = "${var.cluster_name}-vmagent"
  victoriametrics_alertmanager_tailscale_hostname = "${var.cluster_name}-alertmanager"

  victoriametrics_values = {
    nameOverride = "vm-k8s" # avoid too long name errors (default is `victoria-metrics-k8s-stack`, which might lead to e.g. `vmalertmanager-vkms-victoria-metrics-k8s-stack-additional-service`)

    victoria-metrics-operator = {
      nodeSelector = {
        "node-role.kubernetes.io/control-plane" = ""
      }
      tolerations = [
        { key = "node-role.kubernetes.io/control-plane", operator = "Exists", effect = "NoSchedule" }
      ]
    }

    # Use VMSingle by default for simplicity
    vmsingle = {
      enabled = true
      spec = {
        retentionPeriod = "7d"
        storage = {
          accessModes = ["ReadWriteOnce"]
          resources = {
            requests = {
              storage = "10Gi"
            }
          }
        }
      }
      ingress = {
        enabled          = local.victoriametrics_tailscale_ingress_enabled
        ingressClassName = "tailscale"
        hosts            = ["${local.victoriametrics_tailscale_hostname}.${var.tailscale_tailnet}"]
        tls = [{
          hosts = ["${local.victoriametrics_tailscale_hostname}.${var.tailscale_tailnet}"]
        }]
      }
    }

    # Configure node placement
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

    # Configure VMAlert ingress
    vmalert = {
      ingress = {
        enabled          = local.victoriametrics_tailscale_ingress_enabled
        ingressClassName = "tailscale"
        hosts            = ["${local.victoriametrics_vmalert_tailscale_hostname}.${var.tailscale_tailnet}"]
        tls = [{
          hosts = ["${local.victoriametrics_vmalert_tailscale_hostname}.${var.tailscale_tailnet}"]
        }]
      }
    }

    # Configure VMAgent
    vmagent = {
      ingress = {
        enabled          = local.victoriametrics_tailscale_ingress_enabled
        ingressClassName = "tailscale"
        hosts            = ["${local.victoriametrics_vmagent_tailscale_hostname}.${var.tailscale_tailnet}"]
        tls = [{
          hosts = ["${local.victoriametrics_vmagent_tailscale_hostname}.${var.tailscale_tailnet}"]
        }]
      }

      spec = {
        externalLabels = {
          k8s_cluster_name = var.cluster_name
        }
        resources = {
          limits = {
            cpu    = "300m"
            memory = "500Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "200Mi"
          }
        }
      }
    }

    # Configure Alertmanager (ingress disabled, created separately)
    alertmanager = {
      enabled = true

      spec = {
        externalURL = local.victoriametrics_tailscale_ingress_enabled ? "https://${local.victoriametrics_alertmanager_tailscale_hostname}.${var.tailscale_tailnet}" : ""
        serviceSpec = {
          spec = {
            clusterIP = "" # tailscale ingress compat, will create the additional service
          }
        }
      }

      ingress = {
        enabled = false # disabled, created as separate k8s resource since the default ingress targets the headless service
      }

      useManagedConfig = true

      config = {
        route = {
          group_by        = ["alertgroup", "job"]
          group_wait      = "30s"
          group_interval  = "5m"
          repeat_interval = "12h"
          receiver        = "default-receiver"
          routes = concat(
            var.victoriametrics_alertmanager_pushover_enabled ? [
              {
                receiver = "critical-pushover"
                matchers = ["severity=critical"]
                continue = var.victoriametrics_alertmanager_email_enabled
              }
            ] : [],
            var.victoriametrics_alertmanager_email_enabled ? [
              {
                receiver = "critical-warning-email"
                matchers = ["severity=~critical|warning"]
              }
            ] : []
          )
        }
        inhibit_rules = [
          {
            target_matchers = ["severity=~warning|info"]
            source_matchers = ["severity=critical"]
            equal           = ["k8s_cluster_name", "namespace", "alertname"]
          },
          {
            target_matchers = ["severity=info"]
            source_matchers = ["severity=warning"]
            equal           = ["k8s_cluster_name", "namespace", "alertname"]
          }
        ]
        receivers = concat(
          [
            {
              name = "default-receiver"
            }
          ],
          var.victoriametrics_alertmanager_pushover_enabled ? [
            {
              name = "critical-pushover"
              pushover_configs = [
                {
                  token = {
                    key  = "token"
                    name = "pushover-credentials"
                  }
                  user_key = {
                    key  = "user_key"
                    name = "pushover-credentials"
                  }
                  priority = tostring(var.victoriametrics_alertmanager_pushover_priority)
                  sound    = var.victoriametrics_alertmanager_pushover_sound
                  title    = "{{ .GroupLabels.alertname }} - {{ .Status | toUpper }}"
                  message  = "{{ range .Alerts }}{{ .Annotations.summary }}{{ if .Annotations.description }}\n{{ .Annotations.description }}{{ end }}{{ end }}"
                }
              ]
            }
          ] : [],
          var.victoriametrics_alertmanager_email_enabled ? [
            {
              name = "critical-warning-email"
              email_configs = [
                {
                  to            = var.victoriametrics_alertmanager_email_to
                  from          = "${var.cluster_name} <${var.victoriametrics_alertmanager_email_from}>"
                  smarthost     = "${var.victoriametrics_alertmanager_email_smtp_host}:${var.victoriametrics_alertmanager_email_smtp_port}"
                  auth_username = var.victoriametrics_alertmanager_email_smtp_username
                  auth_password = {
                    key  = "password"
                    name = "email-credentials"
                  }
                  subject     = var.victoriametrics_alertmanager_email_subject
                  require_tls = var.victoriametrics_alertmanager_email_require_tls
                  text        = <<-EOT
{{ range .Alerts }}
Alert: {{ .Annotations.summary }}
Severity: {{ .Labels.severity }}
{{ if .Annotations.description }}Description: {{ .Annotations.description }}{{ end }}
{{ if .Annotations.runbook_url }}Runbook: {{ .Annotations.runbook_url }}{{ end }}
Labels: {{ range .Labels.SortedPairs }}{{ .Name }}={{ .Value }} {{ end }}
{{ end }}
EOT
                }
              ]
            }
          ] : []
        )
      }
    }

    prometheus-node-exporter = {
      tolerations = [
        {
          key      = "autoscaler-node"
          operator = "Equal"
          value    = "true"
          effect   = "NoExecute"
        },
        {
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    }

    defaultDashboards = {
      enabled = true
      grafanaOperator = {
        enabled = true
        spec = {
          instanceSelector = {
            matchLabels = {
              dashboards = "grafana"
            }
          }
          allowCrossNamespaceImport = true
        }
      }
    }

    defaultDatasources = {
      grafanaOperator = {
        enabled = true
        spec = {
          instanceSelector = {
            matchLabels = {
              dashboards = "grafana"
            }
          }
          allowCrossNamespaceImport = true
        }
      }
    }

    # Enable Grafana integration
    grafana = {
      enabled               = false
      forceDeployDatasource = true
    }

    # Configure default rules
    defaultRules = {
      create = true
    }

    kubeEtcd = {
      enabled = true

      endpoints = module.k8s.control_plane_private_ipv4_list

      # aligned with talos config
      service = {
        port       = 2381
        targetPort = 2381
      }

      vmScrape = {
        spec = {
          endpoints = [
            {
              port            = "http-metrics"
              scheme          = "http"
              bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token"
            }
          ]
        }
      }
    }

    kubeControllerManager = {
      enabled = true
      vmScrape = {
        spec = {
          endpoints = [
            {
              port            = "http-metrics"
              scheme          = "https"
              bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token"
              tlsConfig = {
                caFile             = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
                serverName         = "localhost" # talos compat
                insecureSkipVerify = true        # talos compat...
              }
            }
          ]
        }
      }
    }

    kubeScheduler = {
      enabled = true
      vmScrape = {
        spec = {
          endpoints = [
            {
              port            = "http-metrics"
              scheme          = "https"
              bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token"
              tlsConfig = {
                caFile             = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
                serverName         = "localhost" # talos compat
                insecureSkipVerify = true        # talos compat...
              }
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_namespace_v1" "victoriametrics" {
  count = var.victoriametrics_enabled ? 1 : 0

  metadata {
    name = "victoriametrics"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "victoriametrics" {
  count = var.victoriametrics_enabled ? 1 : 0

  name      = "vmks"
  namespace = "victoriametrics"

  repository       = var.victoriametrics_helm_repository
  chart            = var.victoriametrics_helm_chart
  version          = var.victoriametrics_helm_version
  create_namespace = false
  wait             = false

  values = [
    yamlencode(
      merge(
        local.victoriametrics_values,
        var.victoriametrics_helm_values
      )
    )
  ]

  depends_on = [
    kubernetes_namespace_v1.victoriametrics,
  ]
}

resource "kubernetes_secret" "victoriametrics_pushover_credentials" {
  count = var.victoriametrics_enabled && var.victoriametrics_alertmanager_pushover_enabled ? 1 : 0

  metadata {
    name      = "pushover-credentials"
    namespace = "victoriametrics"
  }

  type = "Opaque"

  data = {
    token    = var.victoriametrics_alertmanager_pushover_token
    user_key = var.victoriametrics_alertmanager_pushover_user_key
  }

  depends_on = [
    kubernetes_namespace_v1.victoriametrics
  ]
}

resource "kubernetes_secret" "victoriametrics_email_credentials" {
  count = var.victoriametrics_enabled && var.victoriametrics_alertmanager_email_enabled ? 1 : 0

  metadata {
    name      = "email-credentials"
    namespace = "victoriametrics"
  }

  type = "Opaque"

  data = {
    password = var.victoriametrics_alertmanager_email_smtp_password
  }

  depends_on = [
    kubernetes_namespace_v1.victoriametrics
  ]
}

resource "kubernetes_ingress_v1" "victoriametrics_alertmanager_tailscale" {
  count = local.victoriametrics_tailscale_ingress_enabled ? 1 : 0

  metadata {
    name      = "vmalertmanager-vmks-vm-k8s-tailscale"
    namespace = "victoriametrics"
  }

  spec {
    ingress_class_name = "tailscale"

    rule {
      host = "${local.victoriametrics_alertmanager_tailscale_hostname}.${var.tailscale_tailnet}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "vmalertmanager-vmks-vm-k8s-additional-service"
              port {
                name = "http"
              }
            }
          }
        }
      }
    }

    tls {
      hosts = ["${local.victoriametrics_alertmanager_tailscale_hostname}.${var.tailscale_tailnet}"]
    }
  }

  depends_on = [
    helm_release.victoriametrics
  ]
}
