# Configure Kubernetes provider
provider "kubernetes" {
  config_path = "~/.kube/config"                                                               # this is the config path 
}


resource "kubernetes_service_account" "flask_service_account" {                               # create a service account which help in  crucial for managing the identity and permissions of pods 
  metadata {                                                                                  # default service account do not have much permissions
    name      = "flask-serviceaccount"
    namespace = "default"
  }
}


# Secret for HTTP basic auth   used for storing sensitive data 
resource "kubernetes_secret" "nginx_basic_auth" {
  metadata {
    name      = "nginx-basic-auth"
    namespace = "default"
  }

  data = {

    auth = file("${path.module}/.htpasswd")                                                    # ${path.module} refers to the current Terraform module folder and there we have the file htpasswd  .
  }                                                                                            # terraform read the content of the file for the auth 


  type = "Opaque"
}

# ConfigMap for NGINX config
resource "kubernetes_config_map" "nginx_config" {
  metadata {
    name      = "nginx-config"                                                                             # ConfigMaps store non-sensitive configuration files, env values, etc.
    namespace = "default"
  }

  data = {                                                                                                 # default.conf is the name of the file that will be mounted inside the NGINX pod.
    "default.conf" = <<-EOF
      server {
          listen 80;
          server_name vikas.appperfect.com;

           location /healthz {
                return 200 'OK';
                 add_header Content-Type text/plain;
            }

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
      app = "flask"                                                                                          # Used for selecting this pod via Services 
    }
  }

  spec {
    service_account_name = kubernetes_service_account.flask_service_account.metadata[0].name                  # specifies which account used for RBAC

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
        initial_delay_seconds = 3
        period_seconds        = 3

      }

      readiness_probe {
        http_get {
          path = "/"
          port = 5000
        }
        initial_delay_seconds = 3
        period_seconds        = 3

      }

                                        # taint is way to tell the schuduler that on this node you cannnot schedule the pod
                                        # IF A  node is tainted but you still want to schudule the pod on that node then it is toleration 
                                        # if a node is untained and you schudule the pod on it then you again taint the node then there will no effect on it 
    }

    toleration {
      key      = "app"             # that node having key is app = flask then you have to no schudle it 
      operator = "Equal"
      value    = "flask"
      effect   = "NoSchedule"
    }

    node_selector = {               # this pod is schdule on that node having label name  role=flask.
      role = "flask"                # if pod do not match with the label then it will be in pending state.
    }                                # Reason: "No matching node for nodeSelector"
                                      # other option is node affinity 
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

      liveness_probe {
        http_get {
          path = "/healthz"
          port = 80
        }
        initial_delay_seconds = 3
        timeout_seconds       = 1
        period_seconds        = 3
      }
      readiness_probe {
        http_get {
          path = "/healthz"
          port = 80
        }
        initial_delay_seconds = 3
        timeout_seconds       = 1
        period_seconds        = 3
      }







      volume_mount {
        name       = "nginx-config-volume"
        mount_path = "/etc/nginx/conf.d/default.conf"
        sub_path   = "default.conf"                                # 	Mount just one file (default.conf) from the volume, not the whole folder
        read_only  = true
      }

      volume_mount {
        name       = "nginx-auth-volume"
        mount_path = "/etc/nginx/auth/.htpasswd"
        sub_path   = ".htpasswd"                                   #at this intially i am using the auth there and when i check the logs of nginx pod i got the error that 
        read_only  = true                                                          # is it a directory and get error 500 internal server error 
       
      }




    }

    volume {
      name = "nginx-config-volume"

      config_map {                                                # Volume ka data ConfigMap se aayega
        name = kubernetes_config_map.nginx_config.metadata[0].name

        items {                                                   # mount only specific keys from the ConfigMap instead of all of them
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
      value    = "nginx"
      effect   = "NoSchedule"
    }

    node_selector = {
      role = "nginx"
    }
  }
}
#------------------------------service-------------------------------------------------------------------------------------------------------------------
# Provide a stable IP and DNS name to access a set of Pods (selected via labels)
# Service for Flask app 
resource "kubernetes_service" "flask_service" {
  metadata {
    name      = "flask-service"
    namespace = "default"
  }

  spec {
    selector = {                                                  # Service unhi pods ko target karega jinke label me app=flask
      app = "flask"                                               #  this service will route traffic to that pod via http://flask-service:5000 inside the cluster.
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
      port        = 80                                                     # svc listens on 80
      target_port = 80                                                    # Pod's container also exposes port 80
      protocol    = "TCP"
    }

    type = "ClusterIP"                                                        # Default — means service is only accessible inside the cluster
  }
}

# ClusterRole with namespaces access
resource "kubernetes_cluster_role" "pod_reader" {                            # actions (verbs) can be performed on what resources (pods, namespaces)
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
resource "kubernetes_cluster_role_binding" "read_pods_global" {                     # Binds the above role to a ServiceAccount called flask_service_account in the default namespace.
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

#-------------------- Ingress----------------------------------------------------------------------------------------------------------------------------------------------------------
resource "kubernetes_ingress_v1" "pod_check_ingress" {
  metadata {
    name      = "pod-check-ingress"
    namespace = "default"
    annotations = {                                                   # extra instruction 
      "nginx.ingress.kubernetes.io/rewrite-target"  = "/"            # Jo bhi path aaye — /something, use replace karke / bana do.
      "nginx.ingress.kubernetes.io/ssl-redirect"    = "true"         # 	Automatically redirect HTTP → HTTPS
      "nginx.ingress.kubernetes.io/ssl-passthrough" = "true"         # 	TLS traffic directly passed to backend (used if backend like NGINX terminates TLS)
    }
  }

  spec {
    tls {            # used for https configuration 
      hosts       = ["vikas.appperfect.com"]
      secret_name = "vikas-tls-cert"                                # "SSL certificate aur private key is secret me milega jiska naam vikas-tls-cert ha
    }

    rule {
      host = "vikas.appperfect.com"
      http {
        path {
          path      = "/"
          path_type = "Prefix"                                  # path_type = "Prefix"
                                                                # Means: match any path that starts with /
                                                                # Agar aap Exact use karte to sirf / match hota

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


#-----------------------demo for test---------------------------------------------------------------------------------------------------------------------------------

# Namespace to test the namespace is created or not 
resource "kubernetes_namespace" "pod_check" {
  metadata {
    name = "pod-check"                                                                             #this is the namespace for the new pod creation 
  }
}

resource "kubernetes_pod" "test_pod_default" {
  metadata {
    name      = "test-pod-default"
    namespace = kubernetes_namespace.pod_check.metadata[0].name                                    # this is the new pod with name 
  }

  spec {                                                                                           # these are the spec for the new pod
    container {
      name  = "nginx"
      image = "nginx:latest"
    }
  }
}



  # User → https://vikas.appperfect.com/
  # ↓
  # Ingress checks host + path:
  #  - Host = vikas.appperfect.com ✅
  #  - Path starts with / ✅
  #  ↓
  #    Ingress sends request to:
  # nginx-service:80 (ClusterIP)
  # ↓
  # NGINX Pod (container on port 80)
  #  ↓
  # NGINX reverse-proxies to flask-service:5000
