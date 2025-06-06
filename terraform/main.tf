provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Namespace
resource "kubernetes_namespace" "pod_check" {
  metadata {
    name = "pod-check"
  }
}

resource "kubernetes_role" "pod_reader" {
  metadata {
    name      = "pod-reader"
    namespace = kubernetes_namespace.pod_check.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding" "pod_reader_binding" {
  metadata {
    name      = "pod-reader-binding"
    namespace = kubernetes_namespace.pod_check.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.pod_reader.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = kubernetes_namespace.pod_check.metadata[0].name
  }
}


# Deployment
resource "kubernetes_deployment" "pod_check_deployment" {
  metadata {
    name      = "pod-check-deployment"
    namespace = kubernetes_namespace.pod_check.metadata[0].name
    labels = {
      app = "pod-check"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "pod-check"
      }
    }

    template {
      metadata {
        labels = {
          app = "pod-check"
        }
      }

      spec {
        container {
          name  = "pod-check"
          image = "vikasappperfect/pod-check"

          port {
            container_port = 5000
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "pod_check_service" {
  metadata {
    name      = "pod-check-service"
    namespace = kubernetes_namespace.pod_check.metadata[0].name
  }

  spec {
    selector = {
      app = "pod-check"
    }

    port {
      protocol    = "TCP"
      port        = 5000
      target_port = 5000
    }

    type = "ClusterIP"


    
  }
}
