# to interact wih the Kubernetes cluster
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
    "default.conf" = <<-EOF
      server {
          listen 80;
          server_name vikas.appperfect.com;

          location / {
              auth_basic "Restricted Content";
              auth_basic_user_file /etc/nginx/auth/.htpasswd;
              proxy_pass http://127.0.0.1:5000;

              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
          }
      }
    EOF
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
      port        = 80    # Port exposed by the service
    target_port =  80   # Port on the container to forward traffic to
      protocol    = "TCP"
    }

    type = "ClusterIP"          # This service type is used for internal communication within the cluster
  }
}

# Ingress with HTTP only (TLS disabled)
resource "kubernetes_ingress_v1" "pod_check_ingress" {
  metadata {
    name      = "pod-check-ingress"
    namespace = "pod-check"
    annotations = {    # used to configure the ingress controller
      "nginx.ingress.kubernetes.io/rewrite-target"     = "/"
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
      "nginx.ingress.kubernetes.io/ssl-passthrough"    = "true"

    }
  }

  spec {
    tls {      # TLS configuration for the Ingress
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

resource "kubernetes_secret" "nginx_basic_auth" {
  metadata {
    name      = "nginx-basic-auth"
    namespace = kubernetes_namespace.pod_check.metadata[0].name
  }

  data = {
    auth = "dmlrYXM6JGFwcjEkUmkyUEh4bzYkTHBzT0RqYk9UL1ZkT2M5emE3NWRBMA=="
  }


  type = "Opaque"
}


