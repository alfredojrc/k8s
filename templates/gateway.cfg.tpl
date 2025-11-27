global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Default SSL material locations
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

    # Default ciphers to use on SSL-enabled listening sockets
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# Frontend for Kubernetes API Server
frontend k8s-api
    bind *:6443
    mode tcp
    option tcplog
    default_backend k8s-api-backend

# Backend for Kubernetes API Server
backend k8s-api-backend
    mode tcp
    option tcp-check
    balance roundrobin
    %{ for node in master_nodes ~}
    server ${node.name} ${node.ip}:6443 check fall 3 rise 2
    %{ endfor ~}

# Frontend for HTTP traffic
frontend http
    bind *:80
    mode http
    option httplog
    default_backend http-backend

# Backend for HTTP traffic
backend http-backend
    mode http
    balance roundrobin
    option httpchk GET /healthz
    %{ for node in worker_nodes ~}
    server ${node.name} ${node.ip}:30080 check
    %{ endfor ~}

# Frontend for HTTPS traffic
frontend https
    bind *:443
    mode tcp
    option tcplog
    default_backend https-backend

# Backend for HTTPS traffic
backend https-backend
    mode tcp
    balance roundrobin
    %{ for node in worker_nodes ~}
    server ${node.name} ${node.ip}:30443 check
    %{ endfor ~}

# HAProxy Statistics
listen stats
    bind *:9000
    mode http
    stats enable
    stats uri /
    stats realm HAProxy\ Statistics
    stats auth ${stats_credentials}
    stats refresh 10s 