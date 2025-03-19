global_defs {
    router_id HAPROXY${priority == 101 ? "1" : "2"}
    enable_script_security
}

vrrp_script check_haproxy {
    script "/usr/bin/killall -0 haproxy"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state ${priority == 101 ? "MASTER" : "BACKUP"}
    interface ${interface}
    virtual_router_id ${router_id}
    priority ${priority}
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass ${auth_password}
    }
    virtual_ipaddress {
        ${virtual_ip}/24
    }
    track_script {
        check_haproxy
    }
} 