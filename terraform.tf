terraform {
  required_version = ">=1.7.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0.2"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37.1"
    }

    minio = {
      source  = "aminueza/minio"
      version = "~> 3.6.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.0"
    }
  }
}

provider "minio" {
  minio_server   = "${var.location}.your-objectstorage.com"
  minio_region   = var.location
  minio_user     = var.s3_admin_access_key
  minio_password = var.s3_admin_secret_key
  minio_ssl      = true
}

provider "kubernetes" {
  host                   = module.k8s.kubeconfig_data.server
  client_certificate     = module.k8s.kubeconfig_data.cert
  client_key             = module.k8s.kubeconfig_data.key
  cluster_ca_certificate = module.k8s.kubeconfig_data.ca
}

provider "helm" {
  kubernetes = {
    host                   = module.k8s.kubeconfig_data.server
    client_certificate     = module.k8s.kubeconfig_data.cert
    client_key             = module.k8s.kubeconfig_data.key
    cluster_ca_certificate = module.k8s.kubeconfig_data.ca
  }
}
