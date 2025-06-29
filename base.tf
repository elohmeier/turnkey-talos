# Auto-create S3 buckets for backups
resource "minio_s3_bucket" "talos_backup" {
  bucket         = "${var.cluster_name}-talos-backup"
  acl            = "private"
  object_locking = false
}

resource "minio_ilm_policy" "talos_backup" {
  bucket = minio_s3_bucket.talos_backup.bucket
  rule {
    id         = "expire-7d"
    status     = "Enabled"
    expiration = "7d"
  }
}

resource "minio_s3_bucket" "longhorn_backup" {
  bucket         = "${var.cluster_name}-longhorn-backup"
  acl            = "private"
  object_locking = false
}

module "k8s" {
  # source  = "hcloud-k8s/kubernetes/hcloud"
  # version = "1.5.0"

  # source = "git::https://github.com/elohmeier/terraform-hcloud-kubernetes.git?ref=main"
  # source = "git::/Users/enno/repos/github.com/hcloud-k8s/terraform-hcloud-kubernetes?ref=main"
  source = "/Users/enno/repos/github.com/hcloud-k8s/terraform-hcloud-kubernetes"

  cluster_name              = var.cluster_name
  cluster_delete_protection = var.cluster_delete_protection
  hcloud_token              = var.hcloud_token

  control_plane_nodepools = [
    { name = "control", type = "ccx13", location = var.location, count = var.control_plane_count }
  ]
  worker_nodepools = [
    { name = "worker", type = "ccx23", location = var.location, count = var.worker_count },
  ]

  cluster_autoscaler_nodepools = [
    {
      name     = "autoscaler"
      type     = "cpx11"
      location = "fsn1"
      min      = 0
      max      = 2
      labels = {
        "autoscaler-node" = "true"
      }
      taints = [
        "autoscaler-node=true:NoExecute"
      ]
    }
  ]

  cluster_autoscaler_helm_values = {
    extraArgs = {
      enforce-node-group-min-size   = true
      scale-down-delay-after-add    = "45m"
      scale-down-delay-after-delete = "4m"
      scale-down-unneeded-time      = "5m"
    }
  }

  # Export configs for Talos and Kube API access
  cluster_kubeconfig_path  = "kubeconfig"
  cluster_talosconfig_path = "talosconfig"

  # Storage
  hcloud_csi_enabled = false
  longhorn_enabled   = true
  longhorn_helm_values = {
    metrics = {
      serviceMonitor = {
        enabled = true
      }
    }
    defaultBackupStore = {
      backupTarget                 = "s3://${var.cluster_name}-longhorn-backup@${var.location}/"
      backupTargetCredentialSecret = "longhorn-backup-secret"
      pollInterval                 = 300
    }
  }

  # Cilium monitoring
  cilium_service_monitor_enabled = true
  cilium_hubble_enabled          = true
  cilium_hubble_relay_enabled    = true
  cilium_hubble_ui_enabled       = true
  cilium_helm_values = {
    hubble = {
      metrics = {
        enabled = [
          "dns:query;ignoreAAAA",
          "drop",
          "tcp",
          "flow",
          "icmp",
          "http"
        ]
        serviceMonitor = {
          enabled  = true
          interval = "15s"
        }
        dashboards = {
          enabled   = true
          label     = "grafana_dashboard"
          namespace = "kube-system"
        }
      }
      relay = {
        prometheus = {
          enabled = true
          serviceMonitor = {
            enabled  = true
            interval = "15s"
          }
        }
      }
      ui = {
        ingress = var.tailscale_enabled ? {
          enabled   = true
          className = "tailscale"
          hosts     = ["${var.cluster_name}-hubble.${var.tailscale_tailnet}"]
          tls = [{
            hosts = ["${var.cluster_name}-hubble.${var.tailscale_tailnet}"]
          }]
        } : null
      }
    }
    envoy = {
      prometheus = {
        serviceMonitor = {
          enabled  = true
          interval = "15s"
        }
      }
      dashboards = {
        enabled   = true
        label     = "grafana_dashboard"
        namespace = "kube-system"
      }
    }
    operator = {
      prometheus = {
        enabled = true
        serviceMonitor = {
          enabled  = true
          interval = "15s"
        }
      }
      dashboards = {
        enabled   = true
        label     = "grafana_dashboard"
        namespace = "kube-system"
      }
    }
    dashboards = {
      enabled   = true
      label     = "grafana_dashboard"
      namespace = "kube-system"
    }
  }

  # Extras
  cert_manager_enabled  = true
  ingress_nginx_enabled = true

  talos_extra_remote_manifests = [
    "https://github.com/grafana/grafana-operator/releases/download/v5.18.0/crds.yaml"
  ]

  # VictoriaLogs
  talos_extra_kernel_args    = ["talos.logging.kernel=udp://127.0.0.1:6050"]
  talos_logging_destinations = [{ endpoint = "udp://127.0.0.1:6051", format = "json_lines" }]

  talos_backup_s3_endpoint   = "https://${var.location}.your-objectstorage.com"
  talos_backup_s3_region     = var.location
  talos_backup_s3_bucket     = "${var.cluster_name}-talos-backup"
  talos_backup_s3_access_key = var.s3_admin_access_key
  talos_backup_s3_secret_key = var.s3_admin_secret_key
}
