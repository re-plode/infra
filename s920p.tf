resource "terraform_data" "always_run" {
  input = "${timestamp()}"
}

# This doesn't work, so use a fake project to init
# resource "synology_container_network" "netsvc" {
#   name    = "netsvc"
#   subnet  = "192.168.112.0/20"
#   gateway = "192.168.112.1"
# }
resource "synology_container_project" "init" {
  name = "init"
  run  = false

  networks = {
    netsvc = {
      name = "netsvc"
    }
    mediasvc = {
      name = "mediasvc"
    }
  }
}

resource "synology_container_project" "netsvc" {
  name = "netsvc"
  run  = true

  networks = {
    netsvc = {
      name     = "netsvc"
      external = true
    }
    mediasvc = {
      name     = "mediasvc"
      external = true
    }
    media = {
      name     = "media_default"
      external = true
    }
    gtd = {
      name     = "gtd_default"
      external = true
    }
    servarr = {
      name     = "servarr_default"
      external = true
    }
  }

  services = {
    traefik = {
      image   = "traefik:3.6.13"
      restart = "unless-stopped"
      user    = "root"

      networks = {
        netsvc = {
          name = "netsvc"
        }
        mediasvc = {
          name = "mediasvc"
        }
        media = {
          name = "media_default"
        }
        gtd = {
          name = "gtd_default"
        }
        servarr = {
          name = "servarr_default"
        }
      }

      environment = {
        CF_DNS_API_TOKEN = "${var.cloudflare_dns_api_token}"
      }

      labels = {
        "traefik.enable"                             = "true"
        "traefik.http.routers.dashboard.rule"        = "Host(`s920p.replo`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))"
        "traefik.http.routers.dashboard.entrypoints" = "web"
        "traefik.http.routers.dashboard.service"     = "api@internal"
        # "traefik.http.middlewares.ipallowlist.ipallowlist.sourcerange" = "10.42.0.0/16"
        # "traefik.http.routers.dashboard.middlewares"                   = "ipallowlist"
        "traefik.http.services.dashboard.loadbalancer.server.port" = "8080"
      }

      volumes = [{
        type      = "bind"
        source    = "/var/run/docker.sock"
        target    = "/var/run/docker.sock"
        read_only = true
        }, {
        type   = "bind"
        source = "/volume2/var/traefik/traefik.toml"
        target = "/etc/traefik/traefik.toml"
        }, {
        type   = "bind"
        source = "/volume2/var/traefik/acme.json"
        target = "/etc/traefik/acme.json"
        }, {
        type   = "bind"
        source = "/volume2/var/traefik/config"
        target = "/etc/traefik/config"
      }]

      ports = [{
        target    = 80
        published = 80
        protocol  = "tcp"
        }, {
        target    = 443
        published = 443
        protocol  = "tcp"
      }]
    }

    newt = {
      image   = "fosrl/newt:1.11.0"
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

      networks = {
        netsvc = {
          name = "netsvc"
        }
      }

      volumes = [{
        type      = "bind"
        source    = "/var/run/docker.sock"
        target    = "/var/run/docker.sock"
        read_only = true
      }]
    }

    adguardhome = {
      image   = "adguard/adguardhome:v0.107.73"
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

      networks = {
        netsvc = {
          name = "netsvc"
        }
      }

      dns = local.ext_dns

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

  depends_on = [synology_container_project.init]

  lifecycle {
    replace_triggered_by = [
      synology_container_project.init,
      synology_container_project.netsvc.networks,
      terraform_data.always_run
    ]
  }
}

resource "synology_container_project" "mediasvc" {
  name = "mediasvc"
  run  = true

  networks = {
    mediasvc = {
      name     = "mediasvc"
      external = true
    }
  }

  services = {
    jelly = {
      image   = "jellyfin/jellyfin:10.11.7"
      restart = "unless-stopped"
      user    = "${local.s920p_media_uid}:${local.s920p_media_gid}"

      environment = {
        JELLYFIN_PublishedServerUrl = "https://jelly.replo.de"
      }

      labels = {
        "traefik.enable"                                       = "true"
        "traefik.http.routers.jelly.rule"                      = "Host(`jelly.replo.de`)"
        "traefik.http.routers.jelly.entrypoints"               = "websecure"
        "traefik.http.routers.jelly.tls.certresolver"          = "cloudflare"
        "traefik.http.services.jelly.loadbalancer.server.port" = "8096"

        "pangolin.public-resources.jelly.name"                            = "Jellyfin"
        "pangolin.public-resources.jelly.full-domain"                     = "jelly.replo.de"
        "pangolin.public-resources.jelly.protocol"                        = "http"
        "pangolin.public-resources.jelly.auth.sso-enabled"                = "true"
        "pangolin.public-resources.jelly.targets[0].method"               = "http"
        "pangolin.public-resources.jelly.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.jelly.targets[0].port"                 = "8096"
        "pangolin.public-resources.jelly.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.jelly.targets[0].healthcheck.method"   = "http"
        "pangolin.public-resources.jelly.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.jelly.targets[0].healthcheck.port"     = "8096"
      }

      networks = {
        mediasvc = {
          name = "mediasvc"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/dev/dri"
        target = "/dev/dri"
        }, {
        type      = "bind"
        source    = "/volume1/media/sonarr"
        target    = "/data/sonarr"
        read_only = true
        }, {
        type      = "bind"
        source    = "/volume1/media/radarr"
        target    = "/data/radarr"
        read_only = true
        }, {
        type      = "bind"
        source    = "/volume1/media/lidarr"
        target    = "/data/lidarr"
        read_only = true
        }, {
        type      = "bind"
        source    = "/volume1/media/pinchflat"
        target    = "/data/pinchflat"
        read_only = true
        }, {
        type   = "bind"
        source = "/volume2/var/jellyfin/config"
        target = "/config"
        }, {
        type   = "bind"
        source = "/volume2/var/jellyfin/cache"
        target = "/cache"
      }]

      ports = [{
        target    = 8096
        published = 8096
        protocol  = "tcp"
        }, {
        target    = 7359
        published = 7359
        protocol  = "udp"
      }]
    }

    stash = {
      image     = "stashapp/stash:v0.30.1"
      restart   = "unless-stopped"
      mem_limit = "2048M"
      environment = {
        STASH_CONFIG_FILE = "/mnt/stash/config/config.yml"
        USER              = "${local.s920p_media_uid}"
      }

      labels = {
        "traefik.enable"                              = "true"
        "traefik.http.routers.stash.rule"             = "Host(`stash.replo.de`)"
        "traefik.http.routers.stash.entrypoints"      = "websecure"
        "traefik.http.routers.stash.tls.certresolver" = "cloudflare"

        "pangolin.public-resources.stash.name"                            = "Stash"
        "pangolin.public-resources.stash.full-domain"                     = "stash.replo.de"
        "pangolin.public-resources.stash.protocol"                        = "http"
        "pangolin.public-resources.stash.auth.sso-enabled"                = "true"
        "pangolin.public-resources.stash.targets[0].method"               = "http"
        "pangolin.public-resources.stash.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.stash.targets[0].port"                 = "9999"
        "pangolin.public-resources.stash.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.stash.targets[0].healthcheck.method"   = "http"
        "pangolin.public-resources.stash.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.stash.targets[0].healthcheck.port"     = "9999"
      }

      healthcheck = {
        interval     = "10s"
        start_period = "30s"
        test         = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:9999/healthz || exit 1"]
      }

      networks = {
        mediasvc = {
          name = "mediasvc"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/dev/dri"
        target = "/dev/dri"
        }, {
        type   = "bind"
        source = "/volume1/private/stash"
        target = "/mnt/p"
        }, {
        type   = "bind"
        source = "/volume2/var/stash/data"
        target = "/mnt/stash"
        }, {
        type   = "bind"
        source = "/volume2/var/stash/db"
        target = "/mnt/db"
      }]

      ports = [{
        target    = 9999
        published = 9999
        protocol  = "tcp"
      }]
    }
  }

  depends_on = [synology_container_project.init]

  lifecycle {
    replace_triggered_by = [
      synology_container_project.init,
      synology_container_project.mediasvc.networks,
      terraform_data.always_run
    ]
  }
}
