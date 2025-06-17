# Configure Kubernetes provider
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# ───────────────────────────── FIX START: ServiceAccount ─────────────────────────────
resource "kubernetes_service_account" "flask_service_account" {
  metadata {
    name      = "flask-serviceaccount"
    namespace = "default"
  }
}
# ───────────────────────────── FIX END ─────────────────────────────

# Secret for HTTP basic auth
resource "kubernetes_secret" "nginx_basic_auth" {
  metadata {
    name      = "nginx-basic-auth"
    namespace = "default"
  }

  data = {
    auth = filebase64("${path.module}/.htpasswd")
  }

  type = "Opaque"
}

# ConfigMap for NGINX config
resource "kubernetes_config_map" "nginx_config" {
  metadata {
    name      = "nginx-config"
    namespace = "default"
  }

  data = {
    "default.conf" = <<-EOF
      server {
          listen 80;
          server_name vikas.appperfect.com;

          location / {
              auth_basic "Restricted Area";
              auth_basic_user_file /etc/nginx/auth/.htpasswd;

              proxy_pass http://flask-service:5000;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
          }
      }
    EOF
  }
}

# Flask Pod runs only on tainted nodes for flask
resource "kubernetes_pod" "flask_pod" {
  metadata {
    name      = "flask-pod"
    namespace = "default"
    labels = {
      app = "flask"
    }
  }

  spec {
    service_account_name = kubernetes_service_account.flask_service_account.metadata[0].name

    container {
      name  = "flask"
      image = "vikasappperfect/namespace:latest"

      port {
        container_port = 5000
      }

      liveness_probe {
        http_get {
          path = "/"
          port = 5000
        }
        initial_delay_seconds = 10
        period_seconds        = 10
        failure_threshold     = 3
      }

      readiness_probe {
        http_get {
          path = "/"
          port = 5000
        }
        initial_delay_seconds = 5
        period_seconds        = 5
      }
    }

    toleration {
      key      = "app"
      operator = "Equal"
      value    = "flask"
      effect   = "NoSchedule"
    }

    node_selector = {
      role = "flask"
    }
  }
}

# NGINX Pod runs on untainted nodes
resource "kubernetes_pod" "nginx_pod" {
  metadata {
    name      = "nginx-pod"
    namespace = "default"
    labels = {
      app = "nginx"
    }
  }

  spec {
    container {
      name  = "nginx"
      image = "nginx:latest"

      port {
        container_port = 80
      }

      volume_mount {
        name       = "nginx-config-volume"
        mount_path = "/etc/nginx/conf.d/default.conf"
        sub_path   = "default.conf"
        read_only  = true
      }

      volume_mount {
        name       = "nginx-auth-volume"
        mount_path = "/etc/nginx/auth/.htpasswd"
        sub_path   = ".htpasswd"
        read_only  = true
      }

      liveness_probe {
        http_get {
          path = "/"
          port = 80
        }
        initial_delay_seconds = 10
        period_seconds        = 10
        failure_threshold     = 3
      }

      readiness_probe {
        http_get {
          path = "/"
          port = 80
        }
        initial_delay_seconds = 5
        period_seconds        = 5
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

    volume {
      name = "nginx-auth-volume"

      secret {
        secret_name = kubernetes_secret.nginx_basic_auth.metadata[0].name

        items {
          key  = "auth"
          path = ".htpasswd"
        }
      }
    }

    toleration {
      key      = "app"
      operator = "Equal"
      value    = "flask"
      effect   = "NoSchedule"
    }

    node_selector = {
      role = "nginx"
    }
  }
}

# Service for Flask app
resource "kubernetes_service" "flask_service" {
  metadata {
    name      = "flask-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "flask"
    }

    port {
      port        = 5000
      target_port = 5000
      protocol    = "TCP"
    }
  }
}

# Service for NGINX
resource "kubernetes_service" "nginx_service" {
  metadata {
    name      = "nginx-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "nginx"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# ClusterRole with namespaces access
resource "kubernetes_cluster_role" "pod_reader" {
  metadata {
    name = "pod-reader-global"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }
}

# Bind ServiceAccount to ClusterRole
resource "kubernetes_cluster_role_binding" "read_pods_global" {
  metadata {
    name = "pod-reader-binding-global"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.pod_reader.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.flask_service_account.metadata[0].name
    namespace = "default"
  }
}

# Ingress
resource "kubernetes_ingress_v1" "pod_check_ingress" {
  metadata {
    name      = "pod-check-ingress"
    namespace = "default"
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target"  = "/"
      "nginx.ingress.kubernetes.io/ssl-redirect"    = "true"
      "nginx.ingress.kubernetes.io/ssl-passthrough" = "true"
    }
  }

  spec {
    tls {
      hosts       = ["vikas.appperfect.com"]
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
              name = kubernetes_service.nginx_service.metadata[0].name
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

# Namespace to test cross-namespace pod visibility
resource "kubernetes_namespace" "pod_check" {
  metadata {
    name = "pod-check"
  }
}

resource "kubernetes_pod" "test_pod_default" {
  metadata {
    name      = "test-pod-default"
    namespace = kubernetes_namespace.pod_check.metadata[0].name
  }

  spec {
    container {
      name  = "nginx"
      image = "nginx:latest"
    }
  }
}
