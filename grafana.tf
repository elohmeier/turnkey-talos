locals {
  grafana_operator_enabled   = var.grafana_operator_enabled
  grafana_enabled            = var.grafana_enabled && local.grafana_operator_enabled
  grafana_database_enabled   = var.grafana_enabled && var.cloudnative_pg_enabled
  grafana_database_user      = "grafana"
  grafana_tailscale_hostname = "${var.cluster_name}-grafana"

  # Calculate the number of nodes available
  node_count = var.worker_count > 0 ? var.worker_count : var.control_plane_count

  # Grafana replicas logic
  grafana_replicas = var.grafana_replicas > 0 ? var.grafana_replicas : (
    var.grafana_ha_enabled && local.grafana_database_enabled && local.node_count > 1 ? 2 : 1
  )

  # Database replicas logic
  grafana_database_replicas = var.grafana_database_replicas > 0 ? var.grafana_database_replicas : (
    var.grafana_ha_enabled && local.node_count > 1 ? 3 : 1
  )

  grafana_operator_values = {
    # node tolerations for control-plane only clusters
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

  tailscale_urls = {
    argocd                       = var.argocd_enabled && var.tailscale_enabled ? "https://${local.argocd_tailscale_hostname}.${var.tailscale_tailnet}" : null
    argo_workflows               = var.argo_workflows_enabled && var.tailscale_enabled ? "https://${local.argo_workflows_tailscale_hostname}.${var.tailscale_tailnet}" : null
    cilium_hubble_ui             = var.tailscale_enabled ? "https://${var.cluster_name}-hubble.${var.tailscale_tailnet}" : null
    kanidm                       = var.kanidm_enabled && var.tailscale_enabled ? "https://${local.kanidm_tailscale_hostname}.${var.tailscale_tailnet}" : null
    kubetail                     = var.kubetail_enabled && var.tailscale_enabled ? "https://${local.kubetail_tailscale_hostname}.${var.tailscale_tailnet}" : null
    longhorn                     = var.tailscale_enabled ? "https://${local.longhorn_tailscale_hostname}.${var.tailscale_tailnet}" : null
    victoriametrics              = local.victoriametrics_tailscale_ingress_enabled ? "https://${local.victoriametrics_tailscale_hostname}.${var.tailscale_tailnet}" : null
    victoriametrics_grafana      = local.grafana_enabled && var.tailscale_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}" : null
    victoriametrics_vmalert      = local.victoriametrics_tailscale_ingress_enabled ? "https://${local.victoriametrics_vmalert_tailscale_hostname}.${var.tailscale_tailnet}" : null
    victoriametrics_vmagent      = local.victoriametrics_tailscale_ingress_enabled ? "https://${local.victoriametrics_vmagent_tailscale_hostname}.${var.tailscale_tailnet}" : null
    victoriametrics_alertmanager = local.victoriametrics_tailscale_ingress_enabled ? "https://${local.victoriametrics_alertmanager_tailscale_hostname}.${var.tailscale_tailnet}" : null
    victorialogs                 = var.victorialogs_enabled && var.tailscale_enabled ? "https://${local.victorialogs_tailscale_hostname}.${var.tailscale_tailnet}" : null
  }

  home_dashboard_content = <<-EOT
# Services

${join("\n", [
  for name, url in local.tailscale_urls :
  "- [${title(replace(name, "_", " "))}](${url})" if url != null
])}
EOT
}

# Grafana Operator Helm release
resource "helm_release" "grafana_operator" {
  count = local.grafana_operator_enabled ? 1 : 0

  name      = "grafana-operator"
  namespace = "grafana"

  repository       = var.grafana_operator_helm_repository
  chart            = var.grafana_operator_helm_chart
  version          = var.grafana_operator_helm_version
  create_namespace = true
  wait             = false

  values = [
    yamlencode(
      merge(
        local.grafana_operator_values,
        var.grafana_operator_helm_values
      )
    )
  ]
}

resource "kubernetes_secret" "grafana_admin_credentials" {
  count = local.grafana_enabled ? 1 : 0

  metadata {
    name      = "grafana-admin-credentials"
    namespace = "grafana"
  }

  type = "Opaque"

  data = {
    GF_SECURITY_ADMIN_USER     = var.grafana_admin_user
    GF_SECURITY_ADMIN_PASSWORD = var.grafana_admin_password
  }

  depends_on = [helm_release.grafana_operator]
}

resource "random_password" "grafana_db_password" {
  count = local.grafana_database_enabled ? 1 : 0

  length  = 32
  special = true
}

resource "kubernetes_secret" "grafana_db_credentials" {
  count = local.grafana_database_enabled ? 1 : 0

  metadata {
    name      = "grafana-db-cluster-credentials"
    namespace = "grafana"
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = local.grafana_database_user
    password = random_password.grafana_db_password[0].result
  }

  depends_on = [helm_release.grafana_operator]
}

resource "helm_release" "grafana_db" {
  count = local.grafana_database_enabled ? 1 : 0

  name      = "grafana-db"
  namespace = "grafana"

  repository       = var.cloudnative_pg_cluster_helm_repository
  chart            = var.cloudnative_pg_cluster_helm_chart
  version          = var.cloudnative_pg_cluster_helm_version
  create_namespace = false
  wait             = false

  values = [
    yamlencode(
      merge(
        {
          type = "postgresql"
          mode = "standalone"

          version = {
            postgresql = "18"
          }

          cluster = {
            instances = local.grafana_database_replicas

            annotations = {
              "cnpg.io/skipWalArchiving" = "enabled"
            }

            affinity = {
              topologyKey = "kubernetes.io/hostname"
            }

            storage = {
              size = "1Gi"
            }

            initdb = {
              database = "grafana"
              owner    = local.grafana_database_user
              secret = {
                name = "grafana-db-cluster-credentials"
              }
            }

            monitoring = {
              enabled = true
            }
          }
        },
        var.cloudnative_pg_cluster_helm_values
      )
    )
  ]

  depends_on = [
    helm_release.cloudnative_pg,
    helm_release.grafana_operator,
    kubernetes_secret.grafana_db_credentials
  ]
}

# Grafana instance using the operator
resource "kubernetes_manifest" "grafana_instance" {
  count = local.grafana_enabled ? 1 : 0

  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "Grafana"
    metadata = {
      name      = "grafana"
      namespace = "grafana"
      labels = {
        dashboards = "grafana"
      }
    }
    spec = {
      disableDefaultAdminSecret = true
      deployment = {
        spec = {
          replicas = local.grafana_replicas
          template = {
            spec = merge(
              {
                containers = [
                  {
                    name = "grafana"
                    volumeMounts = var.kanidm_enabled && var.kanidm_grafana_oauth_enabled ? [
                      {
                        name      = "oauth-secret"
                        mountPath = "/etc/secrets/grafana-kanidm-oauth2-credentials"
                        readOnly  = true
                      }
                    ] : []
                    env = [
                      {
                        name = "GF_SECURITY_ADMIN_USER"
                        valueFrom = {
                          secretKeyRef = {
                            key  = "GF_SECURITY_ADMIN_USER"
                            name = "grafana-admin-credentials"
                          }
                        }
                      },
                      {
                        name = "GF_SECURITY_ADMIN_PASSWORD"
                        valueFrom = {
                          secretKeyRef = {
                            key  = "GF_SECURITY_ADMIN_PASSWORD"
                            name = "grafana-admin-credentials"
                          }
                        }
                      },
                      {
                        name = "GF_DATABASE_PASSWORD"
                        valueFrom = {
                          secretKeyRef = {
                            key  = "password"
                            name = "grafana-db-cluster-credentials"
                          }
                        }
                      }
                    ]
                  }
                ]
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
              },
              var.kanidm_enabled && var.kanidm_grafana_oauth_enabled ? {
                volumes = [
                  {
                    name = "oauth-secret"
                    secret = {
                      secretName = "grafana-kanidm-oauth2-credentials"
                    }
                  }
                ]
              } : {}
            )
          }
        }
      }
      config = merge(
        {
          log = {
            mode = "console"
          }
          auth = {
            disable_login_form = var.kanidm_enabled && var.kanidm_grafana_oauth_enabled ? "true" : "false"
          }
          server = {
            root_url = var.tailscale_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}" : ""
          }
        },
        var.kanidm_enabled && var.kanidm_grafana_oauth_enabled ? {
          "auth.generic_oauth" = {
            enabled                    = true
            name                       = "Kanidm"
            allow_sign_up              = true
            client_id                  = "grafana"
            client_secret              = "$__file{/etc/secrets/grafana-kanidm-oauth2-credentials/CLIENT_SECRET}"
            scopes                     = "openid profile email groups"
            auth_url                   = "https://${local.kanidm_domain}/ui/oauth2"
            token_url                  = "https://${local.kanidm_domain}/oauth2/token"
            api_url                    = "https://${local.kanidm_domain}/oauth2/openid/userinfo"
            use_pkce                   = true
            use_refresh_token          = true
            role_attribute_path        = "contains(groups[*], 'grafana-admins@${local.kanidm_domain}') && 'Admin' || contains(groups[*], 'grafana-editors@${local.kanidm_domain}') && 'Editor' || 'Viewer'"
            allow_assign_grafana_admin = true
          }
        } : {},
        local.grafana_database_enabled ? merge(
          {
            database = {
              type = "postgres"
              host = "grafana-db-cluster-rw:5432"
              name = "grafana"
              user = local.grafana_database_user
            }
          },
          var.grafana_ha_enabled && local.grafana_replicas > 1 ? {
            unified_alerting = {
              enabled              = true
              ha_listen_address    = "$${POD_IP}:9094"
              ha_peers             = "grafana-alerting:9094"
              ha_advertise_address = "$${POD_IP}:9094"
              ha_peer_timeout      = "15s"
              ha_reconnect_timeout = "2m"
            }
          } : {}
        ) : {}
      )
    }
  }

  depends_on = [
    helm_release.grafana_operator,
    helm_release.grafana_db,
    kubernetes_secret.grafana_admin_credentials,
    kubernetes_manifest.grafana_oauth2_client,
    kubernetes_service_v1.grafana_tailscale_egress,
    kubernetes_service_v1.kanidm_tailscale_egress
  ]
}

# Tailscale ingress for Grafana
resource "kubernetes_ingress_v1" "grafana_tailscale" {
  count = local.grafana_enabled && var.tailscale_enabled ? 1 : 0

  metadata {
    name      = "grafana-tailscale"
    namespace = "grafana"
    annotations = {
      "tailscale.com/expose" = "true"
    }
  }

  spec {
    ingress_class_name = "tailscale"

    rule {
      host = "${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "grafana-service"
              port {
                number = 3000
              }
            }
          }
        }
      }
    }

    tls {
      hosts = ["${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}"]
    }
  }

  depends_on = [helm_release.grafana_operator]
}

resource "kubernetes_manifest" "grafana_home_dashboard" {
  count = local.grafana_enabled ? 1 : 0

  manifest = {
    apiVersion = "grafana.integreatly.org/v1beta1"
    kind       = "GrafanaDashboard"
    metadata = {
      name      = "grafana-home-dashboard"
      namespace = "grafana"
    }
    spec = {
      resyncPeriod = "30s"
      instanceSelector = {
        matchLabels = {
          dashboards = "grafana"
        }
      }
      json = jsonencode({
        uid           = "home"
        title         = "Home"
        schemaVersion = 36
        tags          = ["home"]
        timezone      = "browser"
        panels = [
          {
            type    = "text"
            title   = "Services"
            gridPos = { h = 20, w = 24, x = 0, y = 0 }
            options = {
              mode    = "markdown"
              content = local.home_dashboard_content
            }
          }
        ]
      })
    }
  }

  depends_on = [
    helm_release.grafana_operator
  ]
}

# Create ExternalName service for Grafana Tailscale egress
resource "kubernetes_service_v1" "grafana_tailscale_egress" {
  count = local.grafana_enabled && var.tailscale_enabled ? 1 : 0

  metadata {
    name      = "grafana-tailscale-egress"
    namespace = "grafana"
    annotations = {
      "tailscale.com/tailnet-fqdn" = "${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}"
    }
  }

  spec {
    type          = "ExternalName"
    external_name = "placeholder"
  }

  depends_on = [
    helm_release.grafana_operator,
    helm_release.tailscale
  ]
}
