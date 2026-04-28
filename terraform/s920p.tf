resource "terraform_data" "force_run" {
  input = timestamp()

  # Comment this to force replacement
  lifecycle {
    ignore_changes = [input]
  }
}

resource "synology_filestation_file" "var" {
  path    = "/var/traefik/config/dsm.toml"
  content = <<EOT
[http]
  [http.routers]
    [http.routers.router0]
      entryPoints = ["websecure"]
      service = "service-photos"
      rule = "Host(`photos.replo.de`)"
      [http.routers.router0.tls]
        certResolver = "cloudflare"

    [http.routers.router1]
      entryPoints = ["websecure"]
      service = "service-dsm"
      rule = "Host(`dsm.replo.de`)"
      [http.routers.router1.tls]
        certResolver = "cloudflare"

  [http.services]
    [http.services.service-dsm]
      [http.services.service-dsm.loadBalancer]
        [[http.services.service-dsm.loadBalancer.servers]]
          url = "http://10.42.20.78:5000/"

    [http.services.service-photos]
      [http.services.service-photos.loadBalancer]
        [[http.services.service-photos.loadBalancer.servers]]
          url = "http://10.42.20.78:5080/"
EOT
}

# This doesn't work, so use a fake project to init
# resource "synology_container_network" "netsvc" {
#   name    = "netsvc"
#   subnet  = "192.168.112.0/20"
#   gateway = "192.168.112.1"
# }
resource "synology_container_project" "init" {
  name = "init"
  run  = true

  networks = {
    appsvc = {
      name = "appsvc"
    }
    netsvc = {
      name = "netsvc"
    }
    media = {
      name = "media"
    }
    rss = {
      name = "rss"
    }
    kan = {
      name = "kan"
    }
  }

  services = {
    hello = {
      image = "hello-world:latest"

      labels = {
        "io.portainer.accesscontrol.teams" = "operators"
        "traefik.enable"                   = "false"
      }

      networks = {
        appsvc = {
          name = "appsvc"
        }
        netsvc = {
          name = "netsvc"
        }
        media = {
          name = "media"
        }
        rss = {
          name = "rss"
        }
        kan = {
          name = "kan"
        }
      }
    }
  }

  lifecycle {
    replace_triggered_by = [
      terraform_data.force_run
    ]
  }
}

resource "synology_container_project" "netsvc" {
  name = "netsvc"
  run  = true

  networks = {
    appsvc = {
      name     = "appsvc"
      external = true
    }
    netsvc = {
      name     = "netsvc"
      external = true
    }
    media = {
      name     = "media"
      external = true
    }
    rss = {
      name     = "rss"
      external = true
    }
    kan = {
      name     = "kan"
      external = true
    }
  }

  services = {
    traefik = {
      image   = "traefik:3.6.14"
      restart = "unless-stopped"
      user    = "root"

      networks = {
        appsvc = {
          name = "appsvc"
        }
        netsvc = {
          name = "netsvc"
        }
        media = {
          name = "media"
        }
        rss = {
          name = "rss"
        }
        kan = {
          name = "kan"
        }
      }

      environment = {
        CF_DNS_API_TOKEN = sensitive(data.sops_file.secrets.data["cloudflare.dns_api_token"])
      }

      labels = {
        "io.portainer.accesscontrol.teams"           = "operators"
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
      image   = "fosrl/newt:1.12.0"
      restart = "unless-stopped"
      user    = "root"

      environment = {
        PANGOLIN_ENDPOINT = "https://access.replo.de"
        NEWT_ID           = sensitive(data.sops_file.secrets.data["pangolin.s920p_newt_id"])
        NEWT_SECRET       = sensitive(data.sops_file.secrets.data["pangolin.s920p_newt_secret"])
        DOCKER_SOCKET     = "/var/run/docker.sock"
      }

      labels = {
        "io.portainer.accesscontrol.teams" = "operators"
        "traefik.enable"                   = "false"
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

    olm = {
      image   = "fosrl/olm:1.5.0"
      restart = "unless-stopped"
      user    = "root"

      environment = {
        PANGOLIN_ENDPOINT = "https://access.replo.de"
        OLM_ID            = sensitive(data.sops_file.secrets.data["pangolin.s920p_cli_id"])
        OLM_SECRET        = sensitive(data.sops_file.secrets.data["pangolin.s920p_cli_secret"])
      }

      labels = {
        "io.portainer.accesscontrol.teams" = "operators"
        "traefik.enable"                   = "false"
      }

      cap_add      = ["CAP_NET_ADMIN"]
      network_mode = "host"

      volumes = [{
        type      = "bind"
        source    = "/dev/net/tun"
        target    = "/dev/net/tun"
        read_only = false
      }]
    }

    adguardhome = {
      image   = "adguard/adguardhome:v0.107.74"
      restart = "unless-stopped"
      user    = "root"

      labels = {
        "io.portainer.accesscontrol.teams"                       = "operators"
        "traefik.enable"                                         = "true"
        "traefik.http.routers.adguard.rule"                      = "Host(`dns1.replo.de`)"
        "traefik.http.routers.adguard.entrypoints"               = "websecure"
        "traefik.http.routers.adguard.tls.certresolver"          = "cloudflare"
        "traefik.http.services.adguard.loadbalancer.server.port" = "80"

        "pangolin.public-resources.adguard-local.name"                            = "Adguard (local)"
        "pangolin.public-resources.adguard-local.full-domain"                     = "dns1.replo.de"
        "pangolin.public-resources.adguard-local.protocol"                        = "http"
        "pangolin.public-resources.adguard-local.auth.sso-enabled"                = "true"
        "pangolin.public-resources.adguard-local.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.adguard-local.targets[0].method"               = "http"
        "pangolin.public-resources.adguard-local.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.adguard-local.targets[0].port"                 = "3000"
        "pangolin.public-resources.adguard-local.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.adguard-local.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.adguard-local.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.adguard-local.targets[0].healthcheck.path"     = "/login.html"
        "pangolin.public-resources.adguard-local.targets[0].healthcheck.port"     = "3000"
      }

      network_mode = "host"

      healthcheck = {
        test     = ["CMD", "nslookup", "replo.de", "127.0.0.1"]
        interval = "10s"
        timeout  = "10s"
        retries  = 15
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
    }
  }

  depends_on = [synology_container_project.init]

  lifecycle {
    replace_triggered_by = [
      terraform_data.force_run
    ]
  }
}

resource "synology_container_project" "monsvc" {
  name = "monsvc"
  run  = true

  networks = {
    netsvc = {
      name     = "netsvc"
      external = true
    }
  }

  services = {
    beszel_agent = {
      image   = "henrygd/beszel-agent:0.18.7"
      restart = "unless-stopped"

      labels = {
        "io.portainer.accesscontrol.teams" = "operators"
        "traefik.enable"                   = "false"
      }

      network_mode = "host"

      environment = {
        HUB_URL = "https://up.replo.de"
        KEY     = sensitive(data.sops_file.secrets.data["beszel.pub_key"])
        TOKEN   = sensitive(data.sops_file.secrets.data["beszel.s920p_token"])
        LISTEN  = "45876"
      }

      volumes = [{
        type      = "bind"
        source    = "/var/run/docker.sock"
        target    = "/var/run/docker.sock"
        read_only = true
        }, {
        type      = "bind"
        source    = "/"
        target    = "/extra-filesystems/root__md0"
        read_only = true
        }, {
        type      = "bind"
        source    = "/volume1"
        target    = "/extra-filesystems/volume1__volume1"
        read_only = true
      }]
    }

    dozzle_agent = {
      image   = "amir20/dozzle:v10.5.0"
      restart = "unless-stopped"
      command = ["agent"]

      labels = {
        "io.portainer.accesscontrol.teams" = "operators"
        "traefik.enable"                   = "false"
      }

      hostname = "s920p"
      networks = {
        netsvc = {
          name = "netsvc"
        }
      }

      environment = {
        DOZZLE_NO_ANALYTICS = "true"
      }

      volumes = [{
        type      = "bind"
        source    = "/var/run/docker.sock"
        target    = "/var/run/docker.sock"
        read_only = true
      }]

      ports = [{
        target    = 7007
        published = 7007
        protocol  = "tcp"
      }]
    }

    diun = {
      image    = "crazymax/diun:4.31.0"
      restart  = "unless-stopped"
      hostname = "s920p"

      labels = {
        "io.portainer.accesscontrol.teams" = "operators"
        "traefik.enable"                   = "false"
      }

      environment = {
        TZ                                   = local.tz
        DIUN_WATCH_WORKERS                   = "20"
        DIUN_WATCH_SCHEDULE                  = "0 */6 * * *"
        DIUN_WATCH_JITTER                    = "30s"
        DIUN_WATCH_FIRSTCHECKNOTIF           = "true"
        DIUN_PROVIDERS_DOCKER                = "true"
        DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT = "true"
        DIUN_DEFAULTS_WATCHREPO              = "true"
        DIUN_DEFAULTS_MAXTAGS                = "1"
        DIUN_DEFAULTS_SORTTAGS               = "semver"
        DIUN_DEFAULTS_INCLUDETAGS            = local.diun_include_pattern
        DIUN_DEFAULTS_EXCLUDETAGS            = local.diun_exclude_pattern
        DIUN_NOTIF_MAIL_HOST                 = var.replo_de_smtp_host
        DIUN_NOTIF_MAIL_PORT                 = var.replo_de_smtp_port
        DIUN_NOTIF_MAIL_SSL                  = "false"
        DIUN_NOTIF_MAIL_USERNAME             = sensitive(data.sops_file.secrets.data["brevo.smtp_username"])
        DIUN_NOTIF_MAIL_PASSWORD             = sensitive(data.sops_file.secrets.data["brevo.smtp_password"])
        DIUN_NOTIF_MAIL_FROM                 = var.replo_de_smtp_from
        DIUN_NOTIF_MAIL_TO                   = var.replo_de_smtp_to
        DIUN_NOTIF_MAIL_TEMPLATETITLE        = local.diun_mail_template_title
        DIUN_NOTIF_MAIL_TEMPLATEBODY         = local.diun_mail_template_body
      }

      volumes = [{
        type      = "bind"
        source    = "/var/run/docker.sock"
        target    = "/var/run/docker.sock"
        read_only = true
        }, {
        type      = "bind"
        source    = "/volume2/var/diun"
        target    = "/data"
        read_only = false
      }]
    }

    portainer_agent = {
      image   = "portainer/agent:2.40.0-alpine"
      restart = "unless-stopped"

      labels = {
        "io.portainer.accesscontrol.teams" = "operators"
        "traefik.enable"                   = "false"
      }

      environment = {
        LOG_LEVEL          = "INFO"
        DEBUG              = "0"
        EDGE               = "1"
        EDGE_ID            = sensitive(data.sops_file.secrets.data["portainer.s920p_edge_id"])
        EDGE_KEY           = sensitive(data.sops_file.secrets.data["portainer.s920p_edge_key"])
        EDGE_INSECURE_POLL = "1"
      }

      volumes = [{
        type      = "bind"
        source    = "/var/run/docker.sock"
        target    = "/var/run/docker.sock"
        read_only = true
        }, {
        type      = "bind"
        source    = "/volume2/var/portainer"
        target    = "/data"
        read_only = false
      }]
    }
  }

  depends_on = [synology_container_project.init]

  lifecycle {
    replace_triggered_by = [
      terraform_data.force_run
    ]
  }
}
