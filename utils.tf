locals {
  minio_client_config = {
    version = "10"
    aliases = {
      "${var.cluster_name}" = {
        url       = "https://${var.location}.your-objectstorage.com"
        accessKey = var.s3_admin_access_key
        secretKey = var.s3_admin_secret_key
        api       = "S3v4"
        path      = "auto"
      }
    }
  }

  argocd_server_url = var.argocd_enabled && var.tailscale_enabled ? replace(local.tailscale_urls.argocd, "https://", "") : null
}

resource "terraform_data" "create_minio_config" {
  count = local.minio_client_config != null ? 1 : 0

  triggers_replace = [
    sha1(jsonencode(local.minio_client_config))
  ]

  provisioner "local-exec" {
    when    = create
    quiet   = true
    command = <<-EOT
      set -eu

      mkdir -p .mc
      printf '%s' "$MINIO_CONFIG_CONTENT" > .mc/config.json
      chmod 600 .mc/config.json
    EOT
    environment = {
      MINIO_CONFIG_CONTENT = jsonencode(local.minio_client_config)
    }
  }

  provisioner "local-exec" {
    when       = destroy
    quiet      = true
    on_failure = continue
    command    = <<-EOT
      set -eu

      if [ -f ".mc/config.json" ]; then
        cp -f ".mc/config.json" ".mc/config.json.bak"
      fi
    EOT
  }
}

resource "terraform_data" "create_argocd_server_file" {
  count = local.argocd_server_url != null ? 1 : 0

  triggers_replace = [
    local.argocd_server_url
  ]

  provisioner "local-exec" {
    when    = create
    quiet   = true
    command = <<-EOT
      set -eu

      printf '%s' "$ARGOCD_SERVER_URL" > .argocd_server
      chmod 600 .argocd_server
    EOT
    environment = {
      ARGOCD_SERVER_URL = local.argocd_server_url
    }
  }

  provisioner "local-exec" {
    when       = destroy
    quiet      = true
    on_failure = continue
    command    = <<-EOT
      set -eu

      if [ -f ".argocd_server" ]; then
        cp -f ".argocd_server" ".argocd_server.bak"
      fi
    EOT
  }
}
