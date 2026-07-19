# Create the isolated namespace for Layer-2 Load Balancing
resource "kubernetes_namespace" "metallb_ns" {
  metadata {
    name = "metallb-system"
  }
}

# Deploy official MetalLB controller and network speaker daemons
resource "helm_release" "metallb" {
  depends_on = [kubernetes_namespace.metallb_ns]
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = "0.14.5"
  namespace  = "metallb-system"

  # Inject Layer-2 Pool allocations directly into the chart configurations
  values = [
    yamlencode({
      ipAddressPools = [
        {
          name       = "local-ip-pool"
          addresses  = var.metallb_ip_range
          autoAssign = true
        }
      ]
      l2Advertisements = [
        {
          name           = "local-l2-adv"
          ipAddressPools = ["local-ip-pool"]
        }
      ]
    })
  ]
}

# Deploy official foundational Istio CRDs and Ingress control plane
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  version          = "1.20.0"
  namespace        = "istio-system"
  create_namespace = true
}

resource "helm_release" "istiod" {
  depends_on = [helm_release.istio_base]
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = "1.20.0"
  namespace  = "istio-system"

  # Resource allocations from file 1
  values = [
    yamlencode({
      pilot = {
        resources = {
          requests = {
            cpu    = "50m"
            memory = "256Mi"
          }
        }
      }
    })
  ]

  # --- TRACING CONFIGURATION START --- (from file 2)
  set {
    name  = "meshConfig.enableTracing"
    value = "true"
  }
  set {
    name  = "meshConfig.extensionProviders[0].name"
    value = "otel-tracing"
  }
  set {
    name  = "meshConfig.extensionProviders[0].opentelemetry.port"
    value = "4317"
  }
  set {
    name  = "meshConfig.extensionProviders[0].opentelemetry.service"
    value = "otel-collector.observability.svc.cluster.local"
  }
  # --- TRACING CONFIGURATION END ---
}

resource "helm_release" "istio_ingress" {
  depends_on = [helm_release.istiod]
  name       = "istio-ingressgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  version    = "1.20.0"
  namespace  = "istio-system"
  
  # Crucial: Instructs Terraform to pass the specs and finish immediately
  # without waiting for the physical Proxmox network bridge to assign an IP
  wait       = false
}

# Isolated infrastructure compliance namespace with automatic proxy mesh hooks
resource "kubernetes_namespace" "app_space" {
  metadata {
    name = var.app_namespace
    labels = {
      "istio-injection" = "enabled"
    }
  }
}
