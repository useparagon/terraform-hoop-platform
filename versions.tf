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
  }
}
