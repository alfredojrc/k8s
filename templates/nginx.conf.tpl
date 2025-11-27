user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    # multi_accept on;
}

stream {
    ##
    # Kubernetes API Server Load Balancing (Layer 4 TCP)
    ##
    upstream k8s_api {
        hash $remote_addr consistent;
        %{ for node in master_nodes ~}
        server ${node.ip}:6443 max_fails=3 fail_timeout=10s;
        %{ endfor ~}
    }

    server {
        listen 6443;
        proxy_pass k8s_api;
        proxy_timeout 300s;
        proxy_connect_timeout 1s;
    }

    ##
    # HTTPS Ingress Passthrough (Layer 4 TCP)
    # Passes encrypted traffic directly to Worker Nodes (Cilium Gateway)
    ##
    upstream k8s_ingress_https {
        hash $remote_addr consistent;
        %{ for node in worker_nodes ~}
        server ${node.ip}:30443 max_fails=3 fail_timeout=10s;
        %{ endfor ~}
    }

    server {
        listen 443;
        proxy_pass k8s_ingress_https;
        proxy_timeout 300s;
        proxy_connect_timeout 1s;
    }
}

http {
    ##
    # Basic Settings
    ##
    sendfile on;
    tcp_nopush on;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # Logging Settings
    ##
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    ##
    # HTTP Ingress Load Balancing (Layer 7)
    # Forwards HTTP traffic to Worker Nodes (Cilium Gateway)
    ##
    upstream k8s_ingress_http {
        %{ for node in worker_nodes ~}
        server ${node.ip}:30080; 
        %{ endfor ~}
    }

    server {
        listen 80;
        location / {
            proxy_pass http://k8s_ingress_http;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}