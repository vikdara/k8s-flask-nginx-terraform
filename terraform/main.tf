provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Namespace
resource "kubernetes_namespace" "pod_check" {
  metadata {
    name = "pod-check"
  }
}

# Role to allow pod listing
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

# Role binding
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
    namespace = kubernetes_namespace.pod_check.metadata[0].name
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

# Deployment with Flask + Nginx
resource "kubernetes_deployment" "pod_check" {
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
          name  = "flask-app"
          image = "nightridervikas/pod-check:latest"
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
          liveness_probe {
            http_get {
              path   = "/"
              port   = 80
      
            }
           
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

# ClusterIP Service
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
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# Ingress with HTTP only (TLS disabled)
resource "kubernetes_ingress_v1" "pod_check_ingress" {
  metadata {
    name      = "pod-check-ingress"
    namespace = "pod-check"
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target"     = "/"
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
      "nginx.ingress.kubernetes.io/ssl-passthrough"    = "true"

    }
  }

  spec {
    tls {
      hosts      = ["vikas.appperfect.com"]
      secret_name = "vikas-tls-cert"
    }

    rule {
      host = "vikas.appperfect.com"
      http {
        path {
          path      = "/"
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

