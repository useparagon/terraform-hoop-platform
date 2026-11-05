terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hoop = {
      source  = "hoophq/hoop"
      version = ">= 0.0.21, < 0.1.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0, < 3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0, < 3.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
    terracurl = {
      source  = "devops-rob/terracurl"
      version = ">= 2.11.0, < 3.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }
  }
}
