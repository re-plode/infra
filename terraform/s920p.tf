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

resource "synology_container_project" "mmproviders" {
  name = "mmproviders"
  run  = true

  networks = {
    media = {
      name     = "media"
      external = true
    }
  }

  services = {
    prowlarr = {
      image   = "linuxserver/prowlarr:2.3.5"
      restart = "unless-stopped"

      environment = {
        PUID = local.s920p_media_uid
        PGID = local.s920p_media_gid
        TZ   = local.tz
      }

      labels = {
        "io.portainer.accesscontrol.teams"               = "operators"
        "traefik.enable"                                 = "true"
        "traefik.http.routers.prowlarr.rule"             = "Host(`prowlarr.replo.de`)"
        "traefik.http.routers.prowlarr.entrypoints"      = "websecure"
        "traefik.http.routers.prowlarr.tls.certresolver" = "cloudflare"

        "pangolin.public-resources.prowlarr.name"                            = "Prowlarr"
        "pangolin.public-resources.prowlarr.full-domain"                     = "prowlarr.replo.de"
        "pangolin.public-resources.prowlarr.protocol"                        = "http"
        "pangolin.public-resources.prowlarr.auth.sso-enabled"                = "true"
        "pangolin.public-resources.prowlarr.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.prowlarr.auth.auto-login-idp"             = "2"
        "pangolin.public-resources.prowlarr.targets[0].method"               = "http"
        "pangolin.public-resources.prowlarr.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.prowlarr.targets[0].port"                 = "9696"
        "pangolin.public-resources.prowlarr.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.prowlarr.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.prowlarr.targets[0].healthcheck.path"     = "/ping"
        "pangolin.public-resources.prowlarr.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.prowlarr.targets[0].healthcheck.port"     = "9696"
        "pangolin.public-resources.prowlarr.rules[0].action"                 = "allow"
        "pangolin.public-resources.prowlarr.rules[0].match"                  = "path"
        "pangolin.public-resources.prowlarr.rules[0].value"                  = "/api/*"
      }

      healthcheck = {
        interval     = "10s"
        start_period = "30s"
        test         = ["CMD-SHELL", "curl --fail http://localhost:9696 || exit 1"]
      }

      networks = {
        media = {
          name = "media"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/volume2/var/prowlarr"
        target = "/config"
      }]

      ports = [{
        target    = 9696
        published = 9696
        protocol  = "tcp"
      }]
    }

    nzb = {
      image   = "linuxserver/sabnzbd:4.5.5"
      restart = "unless-stopped"

      environment = {
        PUID = local.s920p_media_uid
        PGID = local.s920p_media_gid
      }

      labels = {
        "io.portainer.accesscontrol.teams"          = "operators"
        "traefik.enable"                            = "true"
        "traefik.http.routers.nzb.rule"             = "Host(`nzb.replo.de`)"
        "traefik.http.routers.nzb.entrypoints"      = "websecure"
        "traefik.http.routers.nzb.tls.certresolver" = "cloudflare"

        "pangolin.public-resources.nzb.name"                            = "SABnzbd"
        "pangolin.public-resources.nzb.full-domain"                     = "nzb.replo.de"
        "pangolin.public-resources.nzb.protocol"                        = "http"
        "pangolin.public-resources.nzb.auth.sso-enabled"                = "true"
        "pangolin.public-resources.nzb.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.nzb.auth.auto-login-idp"             = "2"
        "pangolin.public-resources.nzb.targets[0].method"               = "http"
        "pangolin.public-resources.nzb.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.nzb.targets[0].port"                 = "8081"
        "pangolin.public-resources.nzb.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.nzb.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.nzb.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.nzb.targets[0].healthcheck.port"     = "8081"
        "pangolin.public-resources.nzb.rules[0].action"                 = "allow"
        "pangolin.public-resources.nzb.rules[0].match"                  = "path"
        "pangolin.public-resources.nzb.rules[0].value"                  = "/api/*"
      }

      healthcheck = {
        interval     = "10s"
        start_period = "30s"
        test         = ["CMD-SHELL", "curl --fail http://localhost:8080 || exit 1"]
      }

      networks = {
        media = {
          name = "media"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/volume1/private/sabnzbd"
        target = "/data"
        }, {
        type   = "bind"
        source = "/volume2/var/sabnzbd"
        target = "/config"
      }]

      ports = [{
        target    = 8080
        published = 8081
        protocol  = "tcp"
      }]
    }

    radarr = {
      image   = "linuxserver/radarr:6.1.1"
      restart = "unless-stopped"

      environment = {
        PUID = local.s920p_media_uid
        PGID = local.s920p_media_gid
      }

      labels = {
        "io.portainer.accesscontrol.teams"             = "operators"
        "traefik.enable"                               = "true"
        "traefik.http.routers.radarr.rule"             = "Host(`radarr.replo.de`)"
        "traefik.http.routers.radarr.entrypoints"      = "websecure"
        "traefik.http.routers.radarr.tls.certresolver" = "cloudflare"

        "pangolin.public-resources.radarr.name"                            = "Radarr"
        "pangolin.public-resources.radarr.full-domain"                     = "radarr.replo.de"
        "pangolin.public-resources.radarr.protocol"                        = "http"
        "pangolin.public-resources.radarr.auth.sso-enabled"                = "true"
        "pangolin.public-resources.radarr.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.radarr.auth.auto-login-idp"             = "2"
        "pangolin.public-resources.radarr.targets[0].method"               = "http"
        "pangolin.public-resources.radarr.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.radarr.targets[0].port"                 = "7878"
        "pangolin.public-resources.radarr.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.radarr.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.radarr.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.radarr.targets[0].healthcheck.port"     = "7878"
        "pangolin.public-resources.radarr.rules[0].action"                 = "allow"
        "pangolin.public-resources.radarr.rules[0].match"                  = "path"
        "pangolin.public-resources.radarr.rules[0].value"                  = "/api/*"
      }

      healthcheck = {
        interval     = "10s"
        start_period = "30s"
        test         = ["CMD-SHELL", "curl --fail http://localhost:7878 || exit 1"]
      }

      networks = {
        media = {
          name = "media"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/volume1"
        target = "/data"
        }, {
        type   = "bind"
        source = "/volume2/var/radarr"
        target = "/config"
      }]

      ports = [{
        target    = 7878
        published = 7878
        protocol  = "tcp"
      }]
    }

    sonarr = {
      image   = "linuxserver/sonarr:4.0.17"
      restart = "unless-stopped"

      environment = {
        PUID = local.s920p_media_uid
        PGID = local.s920p_media_gid
      }

      labels = {
        "io.portainer.accesscontrol.teams"             = "operators"
        "traefik.enable"                               = "true"
        "traefik.http.routers.sonarr.rule"             = "Host(`sonarr.replo.de`)"
        "traefik.http.routers.sonarr.entrypoints"      = "websecure"
        "traefik.http.routers.sonarr.tls.certresolver" = "cloudflare"

        "pangolin.public-resources.sonarr.name"                            = "Sonarr"
        "pangolin.public-resources.sonarr.full-domain"                     = "sonarr.replo.de"
        "pangolin.public-resources.sonarr.protocol"                        = "http"
        "pangolin.public-resources.sonarr.auth.sso-enabled"                = "true"
        "pangolin.public-resources.sonarr.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.sonarr.auth.auto-login-idp"             = "2"
        "pangolin.public-resources.sonarr.targets[0].method"               = "http"
        "pangolin.public-resources.sonarr.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.sonarr.targets[0].port"                 = "8989"
        "pangolin.public-resources.sonarr.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.sonarr.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.sonarr.targets[0].healthcheck.path"     = "/ping"
        "pangolin.public-resources.sonarr.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.sonarr.targets[0].healthcheck.port"     = "8989"
        "pangolin.public-resources.sonarr.rules[0].action"                 = "allow"
        "pangolin.public-resources.sonarr.rules[0].match"                  = "path"
        "pangolin.public-resources.sonarr.rules[0].value"                  = "/api/*"
      }

      healthcheck = {
        interval     = "10s"
        start_period = "30s"
        test         = ["CMD-SHELL", "curl --fail http://localhost:8989 || exit 1"]
      }

      networks = {
        media = {
          name = "media"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/volume1"
        target = "/data"
        }, {
        type   = "bind"
        source = "/volume2/var/sonarr"
        target = "/config"
      }]

      ports = [{
        target    = 8989
        published = 8989
        protocol  = "tcp"
      }]
    }

    seerr = {
      image   = "seerr/seerr:v3.2.0"
      restart = "unless-stopped"
      user    = "${local.s920p_media_uid}:${local.s920p_media_gid}"

      environment = {
        TZ        = local.tz
        LOG_LEVEL = "info"
      }

      labels = {
        "io.portainer.accesscontrol.teams"            = "operators"
        "traefik.enable"                              = "true"
        "traefik.http.routers.seerr.rule"             = "Host(`seerr.replo.de`)"
        "traefik.http.routers.seerr.entrypoints"      = "websecure"
        "traefik.http.routers.seerr.tls.certresolver" = "cloudflare"

        "pangolin.public-resources.seerr.name"                            = "Seerr"
        "pangolin.public-resources.seerr.full-domain"                     = "seerr.replo.de"
        "pangolin.public-resources.seerr.protocol"                        = "http"
        "pangolin.public-resources.seerr.auth.sso-enabled"                = "true"
        "pangolin.public-resources.seerr.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.seerr.auth.auto-login-idp"             = "2"
        "pangolin.public-resources.seerr.targets[0].method"               = "http"
        "pangolin.public-resources.seerr.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.seerr.targets[0].port"                 = "5055"
        "pangolin.public-resources.seerr.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.seerr.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.seerr.targets[0].healthcheck.path"     = "/api/v1/status"
        "pangolin.public-resources.seerr.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.seerr.targets[0].healthcheck.port"     = "5055"
        "pangolin.public-resources.seerr.rules[0].action"                 = "allow"
        "pangolin.public-resources.seerr.rules[0].match"                  = "path"
        "pangolin.public-resources.seerr.rules[0].value"                  = "/api/*"
      }

      healthcheck = {
        interval     = "15s"
        start_period = "20s"
        retries      = 3
        timeout      = "3s"
        test         = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:5055/api/v1/status || exit 1"]
      }

      networks = {
        media = {
          name = "media"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/volume2/var/seerr"
        target = "/app/config"
      }]

      ports = [{
        target    = 5055
        published = 5055
        protocol  = "tcp"
      }]
    }

    whisparr = {
      image   = "ghcr.io/hotio/whisparr:v3-v3.3.3"
      restart = "unless-stopped"

      environment = {
        PUID        = local.s920p_media_uid
        PGID        = local.s920p_media_gid
        UMASK       = "022"
        TZ          = local.tz
        WEBUI_PORTS = "6969/tcp"
      }

      labels = {
        "io.portainer.accesscontrol.teams"               = "operators"
        "traefik.enable"                                 = "true"
        "traefik.http.routers.whisparr.rule"             = "Host(`whisparr.replo.de`)"
        "traefik.http.routers.whisparr.entrypoints"      = "websecure"
        "traefik.http.routers.whisparr.tls.certresolver" = "cloudflare"

        "pangolin.public-resources.whisparr.name"                            = "Whisparr"
        "pangolin.public-resources.whisparr.full-domain"                     = "whisparr.replo.de"
        "pangolin.public-resources.whisparr.protocol"                        = "http"
        "pangolin.public-resources.whisparr.auth.sso-enabled"                = "true"
        "pangolin.public-resources.whisparr.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.whisparr.auth.auto-login-idp"             = "2"
        "pangolin.public-resources.whisparr.targets[0].method"               = "http"
        "pangolin.public-resources.whisparr.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.whisparr.targets[0].port"                 = "6969"
        "pangolin.public-resources.whisparr.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.whisparr.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.whisparr.targets[0].healthcheck.path"     = "/"
        "pangolin.public-resources.whisparr.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.whisparr.targets[0].healthcheck.port"     = "6969"
      }

      healthcheck = {
        interval     = "10s"
        start_period = "30s"
        test         = ["CMD-SHELL", "curl --fail http://localhost:6969 || exit 1"]
      }

      networks = {
        media = {
          name = "media"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/volume1/private/"
        target = "/data"
        }, {
        type   = "bind"
        source = "/volume2/var/whisparr"
        target = "/config"
      }]

      ports = [{
        target    = 6969
        published = 6969
        protocol  = "tcp"
      }]
    }

    tube = {
      # TODO: use latest version tag after next release after sha256:1f6090ad9940bb6907f6c542ae0c18ecd3df08cd6cfece6617a424adbfbe3740
      image   = "keglin/pinchflat:latest"
      restart = "unless-stopped"

      environment = {
        TZ        = local.tz
        LOG_LEVEL = "info"
      }

      labels = {
        "io.portainer.accesscontrol.teams"           = "operators"
        "traefik.enable"                             = "true"
        "traefik.http.routers.tube.rule"             = "Host(`tube.replo.de`)"
        "traefik.http.routers.tube.entrypoints"      = "websecure"
        "traefik.http.routers.tube.tls.certresolver" = "cloudflare"

        "pangolin.public-resources.tube.name"                            = "Pinchflat"
        "pangolin.public-resources.tube.full-domain"                     = "tube.replo.de"
        "pangolin.public-resources.tube.protocol"                        = "http"
        "pangolin.public-resources.tube.auth.sso-enabled"                = "true"
        "pangolin.public-resources.tube.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.tube.auth.auto-login-idp"             = "2"
        "pangolin.public-resources.tube.targets[0].method"               = "http"
        "pangolin.public-resources.tube.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.tube.targets[0].port"                 = "8945"
        "pangolin.public-resources.tube.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.tube.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.tube.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.tube.targets[0].healthcheck.port"     = "8945"
      }

      networks = {
        media = {
          name = "media"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/volume1/media/pinchflat"
        target = "/downloads"
        }, {
        type   = "bind"
        source = "/volume2/var/pinchflat"
        target = "/config"
      }]

      ports = [{
        target    = 8945
        published = 8945
        protocol  = "tcp"
      }]
    }

    cast = {
      image   = "advplyr/audiobookshelf:2.34.0"
      restart = "unless-stopped"

      environment = {
        TZ = local.tz
      }

      labels = {
        "io.portainer.accesscontrol.teams"           = "operators"
        "traefik.enable"                             = "true"
        "traefik.http.routers.cast.rule"             = "Host(`cast.replo.de`)"
        "traefik.http.routers.cast.entrypoints"      = "websecure"
        "traefik.http.routers.cast.tls.certresolver" = "cloudflare"

        "pangolin.public-resources.cast.name"                            = "Audiobookshelf"
        "pangolin.public-resources.cast.full-domain"                     = "cast.replo.de"
        "pangolin.public-resources.cast.protocol"                        = "http"
        "pangolin.public-resources.cast.auth.sso-enabled"                = "true"
        "pangolin.public-resources.cast.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.cast.auth.auto-login-idp"             = "2"
        "pangolin.public-resources.cast.targets[0].method"               = "http"
        "pangolin.public-resources.cast.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.cast.targets[0].port"                 = "13378"
        "pangolin.public-resources.cast.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.cast.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.cast.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.cast.targets[0].healthcheck.port"     = "13378"
        "pangolin.public-resources.cast.rules[0].action"                 = "allow"
        "pangolin.public-resources.cast.rules[0].match"                  = "path"
        "pangolin.public-resources.cast.rules[0].value"                  = "/api/*"
        "pangolin.public-resources.cast.rules[1].action"                 = "allow"
        "pangolin.public-resources.cast.rules[1].match"                  = "path"
        "pangolin.public-resources.cast.rules[1].value"                  = "/login"
        "pangolin.public-resources.cast.rules[2].action"                 = "allow"
        "pangolin.public-resources.cast.rules[2].match"                  = "path"
        "pangolin.public-resources.cast.rules[2].value"                  = "/auth/*"
        "pangolin.public-resources.cast.rules[3].action"                 = "allow"
        "pangolin.public-resources.cast.rules[3].match"                  = "path"
        "pangolin.public-resources.cast.rules[3].value"                  = "/feed*"
        "pangolin.public-resources.cast.rules[4].action"                 = "allow"
        "pangolin.public-resources.cast.rules[4].match"                  = "path"
        "pangolin.public-resources.cast.rules[4].value"                  = "/socket.io/"
        "pangolin.public-resources.cast.rules[5].action"                 = "allow"
        "pangolin.public-resources.cast.rules[5].match"                  = "path"
        "pangolin.public-resources.cast.rules[5].value"                  = "/status"
        "pangolin.public-resources.cast.rules[6].action"                 = "allow"
        "pangolin.public-resources.cast.rules[6].match"                  = "path"
        "pangolin.public-resources.cast.rules[6].value"                  = "/logout"
        "pangolin.public-resources.cast.rules[7].action"                 = "allow"
        "pangolin.public-resources.cast.rules[7].match"                  = "path"
        "pangolin.public-resources.cast.rules[7].value"                  = "/ping"
        "pangolin.public-resources.cast.rules[8].action"                 = "allow"
        "pangolin.public-resources.cast.rules[8].match"                  = "path"
        "pangolin.public-resources.cast.rules[8].value"                  = "/public/*"
      }

      networks = {
        media = {
          name = "media"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/volume1/media/audiobookshelf/audiobooks"
        target = "/audiobooks"
        }, {
        type   = "bind"
        source = "/volume1/media/audiobookshelf/podcasts"
        target = "/podcasts"
        }, {
        type   = "bind"
        source = "/volume2/var/audiobookshelf/config"
        target = "/config"
        }, {
        type   = "bind"
        source = "/volume2/var/audiobookshelf/metadata"
        target = "/metadata"
      }]

      ports = [{
        target    = 80
        published = 13378
        protocol  = "tcp"
      }]
    }

    libation = {
      image   = "rmcrackan/libation:13.3.3"
      restart = "unless-stopped"
      user    = "${local.s920p_media_uid}:${local.s920p_media_gid}"

      environment = {
        SLEEP_TIME = "30m"
      }

      labels = {
        "io.portainer.accesscontrol.teams" = "operators"
        "traefik.enable"                   = "false"
      }

      networks = {
        media = {
          name = "media"
        }
      }

      volumes = [{
        type   = "bind"
        source = "/volume1/media/audiobookshelf"
        target = "/data"
        }, {
        type   = "bind"
        source = "/volume2/var/libation"
        target = "/config"
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

resource "synology_container_project" "mmclients" {
  name = "mmclients"
  run  = true

  networks = {
    media = {
      name     = "media"
      external = true
    }
  }

  services = {
    jelly = {
      image   = "jellyfin/jellyfin:10.11.8"
      restart = "unless-stopped"
      user    = "${local.s920p_media_uid}:${local.s920p_media_gid}"

      environment = {
        JELLYFIN_PublishedServerUrl = "https://jelly.replo.de"
      }

      labels = {
        "io.portainer.accesscontrol.teams"                     = "operators"
        "traefik.enable"                                       = "true"
        "traefik.http.routers.jelly.rule"                      = "Host(`jelly.replo.de`)"
        "traefik.http.routers.jelly.entrypoints"               = "websecure"
        "traefik.http.routers.jelly.tls.certresolver"          = "cloudflare"
        "traefik.http.services.jelly.loadbalancer.server.port" = "8096"

        "pangolin.public-resources.jelly.name"                            = "Jellyfin"
        "pangolin.public-resources.jelly.full-domain"                     = "jelly.replo.de"
        "pangolin.public-resources.jelly.protocol"                        = "http"
        "pangolin.public-resources.jelly.auth.sso-enabled"                = "true"
        "pangolin.public-resources.jelly.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.jelly.auth.auto-login-idp"             = "2"
        "pangolin.public-resources.jelly.targets[0].method"               = "http"
        "pangolin.public-resources.jelly.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.jelly.targets[0].port"                 = "8096"
        "pangolin.public-resources.jelly.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.jelly.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.jelly.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.jelly.targets[0].healthcheck.port"     = "8096"
        "pangolin.public-resources.jelly.rules[0].action"                 = "allow"
        "pangolin.public-resources.jelly.rules[0].match"                  = "path"
        "pangolin.public-resources.jelly.rules[0].value"                  = "/system/info/public"
      }

      networks = {
        media = {
          name = "media"
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
      image     = "stashapp/stash:v0.31.1"
      restart   = "unless-stopped"
      mem_limit = "2048M"
      environment = {
        STASH_CONFIG_FILE = "/mnt/stash/config/config.yml"
        USER              = "${local.s920p_media_uid}"
      }

      labels = {
        "io.portainer.accesscontrol.teams"            = "operators"
        "traefik.enable"                              = "true"
        "traefik.http.routers.stash.rule"             = "Host(`stash.replo.de`)"
        "traefik.http.routers.stash.entrypoints"      = "websecure"
        "traefik.http.routers.stash.tls.certresolver" = "cloudflare"

        "pangolin.public-resources.stash.name"                            = "Stash"
        "pangolin.public-resources.stash.full-domain"                     = "stash.replo.de"
        "pangolin.public-resources.stash.protocol"                        = "http"
        "pangolin.public-resources.stash.auth.sso-enabled"                = "true"
        "pangolin.public-resources.stash.auth.sso-roles[0]"               = "Member"
        "pangolin.public-resources.stash.auth.auto-login-idp"             = "2"
        "pangolin.public-resources.stash.targets[0].method"               = "http"
        "pangolin.public-resources.stash.targets[0].hostname"             = "172.17.0.1"
        "pangolin.public-resources.stash.targets[0].port"                 = "9999"
        "pangolin.public-resources.stash.targets[0].healthcheck.enabled"  = "true"
        "pangolin.public-resources.stash.targets[0].healthcheck.method"   = "GET"
        "pangolin.public-resources.stash.targets[0].healthcheck.hostname" = "172.17.0.1"
        "pangolin.public-resources.stash.targets[0].healthcheck.port"     = "9999"
      }

      healthcheck = {
        interval     = "10s"
        start_period = "30s"
        test         = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:9999/healthz || exit 1"]
      }

      networks = {
        media = {
          name = "media"
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
      terraform_data.force_run
    ]
  }
}
