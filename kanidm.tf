locals {
  kanidm_enabled            = var.kanidm_enabled
  kanidm_tailscale_hostname = "${var.cluster_name}-kanidm"
  kanidm_domain             = var.kanidm_domain != "" ? var.kanidm_domain : (var.tailscale_enabled ? "${local.kanidm_tailscale_hostname}.${var.tailscale_tailnet}" : "kanidm.${var.cluster_name}.local")

  kaniop_values = {
    image = {
      repository = var.kaniop_image_repository
      tag        = var.kaniop_image_tag
    }
    logging = {
      level = "info,kaniop=trace"
    }
    metrics = {
      enabled = true
      service = {
        type = "ClusterIP"
        port = 8080
      }
      serviceMonitor = {
        enabled  = true
        interval = "30s"
      }
    }
  }


  grafana_groups = var.kanidm_grafana_oauth_enabled ? [
    { name = "grafana-users", members = var.kanidm_initial_user.enabled ? [var.kanidm_initial_user.name] : [] },
    { name = "grafana-admins", members = var.kanidm_initial_user.enabled ? [var.kanidm_initial_user.name] : [] },
    { name = "grafana-editors", members = [] }
  ] : []

  argo_workflows_groups = var.argo_workflows_enabled && var.kanidm_argo_workflows_oauth_enabled ? [
    { name = "argo-workflows-users", members = var.kanidm_initial_user.enabled ? [var.kanidm_initial_user.name] : [] },
    { name = "argo-workflows-admins", members = var.kanidm_initial_user.enabled ? [var.kanidm_initial_user.name] : [] }
  ] : []

  kanidm_values = {
    domain = local.kanidm_domain

    # Enable watching OAuth2 clients in all namespaces
    oauth2ClientNamespaceSelector = {}

    replicaGroups = [
      {
        name     = "default"
        replicas = var.kanidm_replicas
      }
    ]

    image           = var.kanidm_image
    imagePullPolicy = var.kanidm_image_pull_policy

    storage = {
      volumeClaimTemplate = {
        metadata = {
          name = "kanidm-data"
        }
        spec = {
          accessModes = ["ReadWriteOnce"]
          resources = {
            requests = {
              storage = var.kanidm_storage_size
            }
          }
        }
      }
    }

    certManager = {
      enabled    = true
      issuer     = var.kanidm_cert_issuer
      issuerKind = var.kanidm_cert_issuer_kind
    }

    ingress = {
      enabled   = var.kanidm_ingress_enabled
      className = var.tailscale_enabled ? "tailscale" : ""
      host      = var.tailscale_enabled ? "${local.kanidm_tailscale_hostname}.${var.tailscale_tailnet}" : local.kanidm_domain
      annotations = var.tailscale_enabled ? {
        "tailscale.com/experimental-forward-cluster-traffic-via-ingress" = "true"
      } : {}
    }

    user = var.kanidm_initial_user

    oauth2Clients = var.kanidm_oauth2_clients
    groups        = concat(local.grafana_groups, local.argo_workflows_groups, var.kanidm_groups)

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
}

resource "helm_release" "kaniop" {
  count = local.kanidm_enabled ? 1 : 0

  name      = "kaniop"
  namespace = "kanidm"

  repository       = var.kaniop_helm_repository
  chart            = var.kaniop_helm_chart
  version          = var.kaniop_helm_version
  create_namespace = true
  wait             = false

  values = [
    yamlencode(
      merge(
        local.kaniop_values,
        var.kaniop_helm_values
      )
    )
  ]
}

resource "helm_release" "kanidm" {
  count = local.kanidm_enabled ? 1 : 0

  name      = "kanidm"
  namespace = "kanidm"

  repository       = var.kanidm_helm_repository != "" ? var.kanidm_helm_repository : null
  chart            = var.kanidm_helm_repository != "" ? var.kanidm_helm_chart : "${path.module}/charts/kanidm"
  version          = var.kanidm_helm_version != "" ? var.kanidm_helm_version : null
  create_namespace = true
  wait             = false

  values = [
    yamlencode(
      merge(
        local.kanidm_values,
        var.kanidm_helm_values
      )
    )
  ]

  depends_on = [
    helm_release.kaniop,
    helm_release.tailscale,
  ]
}

# Create OAuth2 client for Grafana in the grafana namespace
resource "kubernetes_manifest" "grafana_oauth2_client" {
  count = local.kanidm_enabled && var.kanidm_grafana_oauth_enabled ? 1 : 0

  manifest = {
    apiVersion = "kaniop.rs/v1beta1"
    kind       = "KanidmOAuth2Client"
    metadata = {
      name      = "grafana"
      namespace = "grafana"
    }
    spec = {
      kanidmRef = {
        name      = "kanidm"
        namespace = "kanidm"
      }
      displayname = "Grafana"
      origin      = var.tailscale_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}" : "https://grafana.${var.cluster_name}.local"
      redirectUrl = [
        var.tailscale_enabled ? "https://${local.grafana_tailscale_hostname}.${var.tailscale_tailnet}/login/generic_oauth" : "https://grafana.${var.cluster_name}.local/login/generic_oauth"
      ]
      scopeMap = [
        {
          group  = "grafana-users@${local.kanidm_domain}"
          scopes = ["email", "groups", "openid", "profile"]
        }
      ]
      supScopeMap = [
        {
          group  = "grafana-admins@${local.kanidm_domain}"
          scopes = ["admin"]
        },
        {
          group  = "grafana-editors@${local.kanidm_domain}"
          scopes = ["editor"]
        }
      ]
    }
  }

  depends_on = [
    helm_release.kanidm,
    helm_release.kaniop,
    helm_release.grafana_operator
  ]
}

# Create ExternalName service for Kanidm Tailscale egress
resource "kubernetes_service_v1" "kanidm_tailscale_egress" {
  count = local.kanidm_enabled && var.tailscale_enabled ? 1 : 0

  metadata {
    name      = "kanidm-tailscale-egress"
    namespace = "kanidm"
    annotations = {
      "tailscale.com/tailnet-fqdn" = "${local.kanidm_tailscale_hostname}.${var.tailscale_tailnet}"
    }
  }

  spec {
    type          = "ExternalName"
    external_name = "placeholder"
  }

  depends_on = [
    helm_release.kanidm,
    helm_release.tailscale,
    helm_release.coredns
  ]
}
