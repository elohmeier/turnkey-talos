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
