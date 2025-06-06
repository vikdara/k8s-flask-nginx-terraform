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


# ConfigMap for nginx.conf
resource "kubernetes_config_map" "nginx_config" {
  metadata {
    name      = "nginx-config"
    namespace = "pod-check"
  }

  data = {
    "default.conf" = <<-EOT
      server {
          listen 80;
          location / {
              proxy_pass http://localhost:5000;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
          }
      }
    EOT
  }
}

# Deployment update (add nginx container)
resource "kubernetes_deployment" "pod_check" {
  # ... your existing deployment config ...
  spec {
    template {
      spec {
        container {
          name  = "flask-app"
          image = "vikasappperfect/pod-check:latest"
          port {
            container_port = 5000
          }
        }

        container {
          name  = "nginx"
          image = "nginx:stable-alpine"
          port {
            container_port = 80
          }

          volume_mount {
            name       = "nginx-config-volume"
            mount_path = "/etc/nginx/conf.d/default.conf"
            sub_path   = "default.conf"
          }
        }

        volume {
          name = "nginx-config-volume"
          config_map {
            name = kubernetes_config_map.nginx_config.metadata[0].name
            items {
              key  = "default.conf"
              path = "default.conf"
            }
          }
        }
      }
    }
  }
}

# Service update to expose port 80
resource "kubernetes_service" "pod_check_service" {
  metadata {
    name      = "pod-check-service"
    namespace = "pod-check"
  }

  spec {
    selector = {
      app = kubernetes_deployment.pod_check.metadata[0].labels.app
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# Ingress resource
resource "kubernetes_ingress" "pod_check_ingress" {
  metadata {
    name      = "pod-check-ingress"
    namespace = "pod-check"
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }

  spec {
    rule {
      host = "vikas.appperfect.com"
      http {
        path {
          path     = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.pod_check_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
