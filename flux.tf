locals {
  flux_enabled = var.flux_enabled

  flux_values = {
    installCRDs        = true
    watchAllNamespaces = var.flux_watch_all_namespaces
    logLevel           = var.flux_log_level
    clusterDomain      = "cluster.local"

    # Configure tolerations and node selector if running on control plane nodes only
    helmController = {
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

    kustomizeController = {
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

    sourceController = {
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

    notificationController = {
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

    imageReflectionController = {
      create = var.flux_image_automation_enabled
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

    imageAutomationController = {
      create = var.flux_image_automation_enabled
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

    prometheus = {
      podMonitor = {
        create = var.flux_prometheus_podmonitor_enabled
      }
    }
  }
}

resource "tls_private_key" "flux" {
  count = local.flux_enabled ? 1 : 0

  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "kubernetes_namespace" "flux_system" {
  count = local.flux_enabled ? 1 : 0

  metadata {
    name = "flux-system"
  }
}

resource "kubernetes_secret" "ssh_keypair" {
  count = local.flux_enabled ? 1 : 0

  metadata {
    name      = "ssh-keypair"
    namespace = "flux-system"
  }

  type = "Opaque"

  data = {
    "identity.pub" = tls_private_key.flux[0].public_key_openssh
    "identity"     = tls_private_key.flux[0].private_key_pem
    "known_hosts"  = "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
  }

  depends_on = [kubernetes_namespace.flux_system[0]]
}

resource "helm_release" "flux" {
  count = local.flux_enabled ? 1 : 0

  name      = "flux"
  namespace = "flux-system"

  repository       = var.flux_helm_repository
  chart            = var.flux_helm_chart
  version          = var.flux_helm_version
  create_namespace = false
  wait             = false

  depends_on = [kubernetes_namespace.flux_system[0]]

  values = [
    yamlencode(
      merge(
        local.flux_values,
        var.flux_helm_values
      )
    )
  ]
}
