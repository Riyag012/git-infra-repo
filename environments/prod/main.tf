variable "metallb_ip_range" {
  type = list(string)
}

variable "kubeconfig_path" {
  type = string
}

# 1. Add the variable declaration
variable "app_namespace" {
  type = string
}

module "prod_cluster_ingress" {
  source           = "../../modules/cluster_ingress_base"
  metallb_ip_range = var.metallb_ip_range
  app_namespace    = var.app_namespace
  
  providers = {
    kubernetes = kubernetes
    helm       = helm
  }
}