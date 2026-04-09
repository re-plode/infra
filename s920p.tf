resource "synology_container_project" "netsvc" {
  name = "netsvc"
  run  = true

  services = {
    newt = {
      image   = "fosrl/newt:latest"
      restart = "unless-stopped"
      user    = "root"

      environment = {
        PANGOLIN_ENDPOINT = "https://replo.de"
        NEWT_ID           = "${var.s920p_newt_id}"
        NEWT_SECRET       = "${var.s920p_newt_secret}"
        DOCKER_SOCKET     = "/var/run/docker.sock"
      }

      labels = {
        "traefik.enable" = "false"
      }

      volumes = [{
        type      = "bind"
        source    = "/var/run/docker.sock"
        target    = "/var/run/docker.sock"
        read_only = true
      }]
    }

    adguardhome = {
      image   = "adguard/adguardhome:latest"
      restart = "unless-stopped"
      user    = "root"

      labels = {
        "traefik.enable"                                         = "true"
        "traefik.http.routers.adguard.rule"                      = "Host(`adguard.replo.de`)"
        "traefik.http.routers.adguard.entrypoints"               = "websecure"
        "traefik.http.routers.adguard.tls.certresolver"          = "cloudflare"
        "traefik.http.services.adguard.loadbalancer.server.port" = "80"

        "pangolin.public-resources.adguard-local.name"                            = "Adguard (local)"
        "pangolin.public-resources.adguard-local.full-domain"                     = "adguard.replo.de"
        "pangolin.public-resources.adguard-local.protocol"                        = "http"
        "pangolin.public-resources.adguard-local.auth.sso-enabled"                = "true"
        "pangolin.public-resources.adguard-local.targets[0].method"               = "http"
        "pangolin.public-resources.adguard-local.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.adguard-local.targets[0].port"                 = "3000"
        "pangolin.public-resources.adguard-local.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.adguard-local.targets[0].healthcheck.method"   = "http"
        "pangolin.public-resources.adguard-local.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.adguard-local.targets[0].healthcheck.port"     = "3000"
      }

      dns = [
        "9.9.9.9",
        "149.112.112.112"
      ]

      volumes = [{
        type   = "bind"
        source = "/volume2/var/adguard/work"
        target = "/opt/adguardhome/work"
        }, {
        type   = "bind"
        source = "/volume2/var/adguard/conf"
        target = "/opt/adguardhome/conf"
      }]

      ports = [{
        target    = 53
        published = 53
        protocol  = "udp"
        }, {
        target    = 80
        published = 3000
        protocol  = "tcp"
      }]
    }
  }
}
