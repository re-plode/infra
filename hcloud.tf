resource "hcloud_ssh_key" "ssh_keys" {
  for_each = tomap({
    "russellc@fedora"  = "config/ssh/id_ed25519_fedora.pub"
    "russellc@ipadpro" = "config/ssh/id_ed25519_ipadpro.pub"
    "russellc@github"  = "config/ssh/id_ed25519_github.pub"
    "russellc@mbpnix"  = "config/ssh/id_ed25519_mbpnix.pub"
  })
  name       = each.key
  public_key = file(each.value)

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_firewall" "internal_net_firewall" {
  name = "internal-net-firewall"
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = local.all_ips
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = local.all_ips
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = local.all_ips
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8000"
    source_ips = local.all_ips
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = local.all_ips
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "21820"
    source_ips = local.all_ips
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = local.all_ips
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51821"
    source_ips = local.all_ips
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_server" "internal_net" {
  name        = "internal-net"
  image       = "docker-ce"
  server_type = "cax11"
  location    = "nbg1"
  backups     = false

  user_data = file("config/cloudinit/hcloud.yml")

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.internal_net_ip.id
    ipv6_enabled = true
  }

  ssh_keys = [
    hcloud_ssh_key.ssh_keys["russellc@fedora"].id,
    hcloud_ssh_key.ssh_keys["russellc@ipadpro"].id,
    hcloud_ssh_key.ssh_keys["russellc@github"].id,
    hcloud_ssh_key.ssh_keys["russellc@mbpnix"].id
  ]

  delete_protection  = true
  rebuild_protection = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_volume" "internal_net_vol" {
  name              = "internal-net-vol"
  size              = 10
  format            = "ext4"
  location          = "nbg1"
  delete_protection = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_primary_ip" "internal_net_ip" {
  name              = "primary_ip-126634539"
  type              = "ipv4"
  location          = "nbg1"
  assignee_type     = "server"
  delete_protection = true
  auto_delete       = false
}

resource "hcloud_firewall_attachment" "internal_net_firewall_attachment" {
  firewall_id = hcloud_firewall.internal_net_firewall.id
  server_ids  = [hcloud_server.internal_net.id]
}

resource "hcloud_volume_attachment" "internal_net_vol_attachment" {
  volume_id = hcloud_volume.internal_net_vol.id
  server_id = hcloud_server.internal_net.id
  automount = true
}

resource "docker_network" "pangolin" {
  provider = docker.internal-net
  name     = "pangolin"
  driver   = "bridge"
}
resource "docker_network" "netsvc" {
  provider = docker.internal-net
  name     = "netsvc"
  driver   = "bridge"

  ipam_config {
    gateway = "172.254.0.1"
    subnet  = "172.254.0.0/16"
  }
}

resource "docker_image" "images" {
  for_each = tomap({
    "fosrl/pangolin"                    = "1.17.1"
    "fosrl/gerbil"                      = "1.3.1"
    "crowdsecurity/crowdsec"            = "v1.7.7-debian"
    "traefik"                           = "3.6.13"
    "fosrl/newt"                        = "1.11.0"
    "fosrl/olm"                         = "1.4.4"
    "adguard/adguardhome"               = "v0.107.74"
    "ghcr.io/bakito/adguardhome-sync"   = "v0.9.0"
    "ghcr.io/wg-easy/wg-easy"           = "15.2.2"
    "ghcr.io/pocket-id/pocket-id"       = "v2.6.2"
    "henrygd/beszel"                    = "0.18.7"
    "henrygd/beszel-agent"              = "0.18.7"
    "crazymax/diun"                     = "4.31.0"
    "portainer/portainer-ce"            = "2.40.0-alpine"
    "amir20/dozzle"                     = "v10.4.1"
    "quay.io/oauth2-proxy/oauth2-proxy" = "v7.15.2-alpine"
    "caddy"                             = "2.11.2-alpine"
  })
  provider = docker.internal-net
  name     = "${each.key}:${each.value}"
}

resource "docker_container" "pangolin" {
  provider = docker.internal-net
  name     = "pangolin"
  image    = docker_image.images["fosrl/pangolin"].image_id
  restart  = "unless-stopped"

  env = [
    "SERVER_SECRET=${sensitive(data.sops_file.secrets.data["pangolin.server_secret"])}",
    "EMAIL_SMTP_PASS=${sensitive(data.sops_file.secrets.data["brevo.smtp_password"])}"
  ]

  labels {
    label = "io.portainer.accesscontrol.teams"
    value = "operators"
  }

  networks_advanced {
    name = docker_network.pangolin.name
  }

  volumes {
    container_path = "/app/config"
    host_path      = "/var/lib/containers/pangolin/config"
    read_only      = false
  }

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:3001/api/v1/"]
    interval = "10s"
    timeout  = "10s"
    retries  = 15
  }
}

resource "docker_container" "gerbil" {
  provider = docker.internal-net
  name     = "gerbil"
  image    = docker_image.images["fosrl/gerbil"].image_id
  restart  = "unless-stopped"

  command = [
    "--reachableAt=http://gerbil:3004",
    "--generateAndSaveKeyTo=/var/config/key",
    "--remoteConfig=http://pangolin:3001/api/v1/"
  ]

  labels {
    label = "io.portainer.accesscontrol.teams"
    value = "operators"
  }

  capabilities {
    add = ["CAP_NET_ADMIN", "CAP_SYS_MODULE"]
  }

  networks_advanced {
    name = docker_network.pangolin.name
  }
  networks_advanced {
    name         = docker_network.netsvc.name
    ipv4_address = "172.254.0.4"
  }

  volumes {
    container_path = "/var/config"
    host_path      = "/var/lib/containers/gerbil/config"
    read_only      = false
  }

  ports {
    internal = 51820
    external = 51820
    protocol = "udp"
  }
  ports {
    internal = 21820
    external = 21820
    protocol = "udp"
  }
  ports {
    internal = 443
    external = 443
    protocol = "tcp"
  }
  ports {
    internal = 80
    external = 80
    protocol = "tcp"
  }

  depends_on = [docker_container.pangolin]
}

resource "docker_container" "newt" {
  provider = docker.internal-net
  name     = "newt"
  image    = docker_image.images["fosrl/newt"].image_id
  restart  = "unless-stopped"

  env = [
    "PANGOLIN_ENDPOINT=https://access.replo.de",
    "NEWT_ID=${sensitive(data.sops_file.secrets.data["pangolin.hcloud_newt_id"])}",
    "NEWT_SECRET=${sensitive(data.sops_file.secrets.data["pangolin.hcloud_newt_secret"])}",
    "DOCKER_SOCKET=/var/run/docker.sock"
  ]

  labels {
    label = "io.portainer.accesscontrol.teams"
    value = "operators"
  }

  networks_advanced {
    name         = docker_network.netsvc.name
    ipv4_address = "172.254.0.5"
  }

  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
    read_only      = true
  }
}

resource "docker_container" "olm" {
  provider = docker.internal-net
  name     = "olm"
  image    = docker_image.images["fosrl/olm"].image_id
  restart  = "unless-stopped"

  network_mode = "host"

  env = [
    "PANGOLIN_ENDPOINT=https://access.replo.de",
    "OLM_ID=${sensitive(data.sops_file.secrets.data["pangolin.hcloud_cli_id"])}",
    "OLM_SECRET=${sensitive(data.sops_file.secrets.data["pangolin.hcloud_cli_secret"])}",
  ]

  labels {
    label = "io.portainer.accesscontrol.teams"
    value = "operators"
  }

  capabilities {
    add = ["CAP_NET_ADMIN"]
  }

  volumes {
    container_path = "/dev/net/tun"
    host_path      = "/dev/net/tun"
    read_only      = false
  }
}

resource "docker_container" "traefik" {
  provider     = docker.internal-net
  name         = "traefik"
  image        = docker_image.images["traefik"].image_id
  restart      = "unless-stopped"
  network_mode = "container:${docker_container.gerbil.id}"

  command = ["--configFile=/etc/traefik/traefik_config.yml"]

  labels {
    label = "io.portainer.accesscontrol.teams"
    value = "operators"
  }

  volumes {
    container_path = "/etc/traefik"
    host_path      = "/var/lib/containers/traefik/etc"
    read_only      = true
  }
  volumes {
    container_path = "/letsencrypt"
    host_path      = "/var/lib/containers/traefik/letsencrypt"
    read_only      = false
  }
  volumes {
    container_path = "/var/log/traefik"
    host_path      = "/var/lib/containers/traefik/logs"
    read_only      = false
  }

  depends_on = [docker_container.pangolin, docker_container.gerbil]
}

resource "docker_container" "crowdsec" {
  provider = docker.internal-net
  name     = "crowdsec"
  image    = docker_image.images["crowdsecurity/crowdsec"].image_id
  restart  = "unless-stopped"

  dns = [
    "172.254.0.1",
    "10.42.20.78
  ]

  env = [
    "COLLECTIONS=crowdsecurity/traefik crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules crowdsecurity/linux",
  ]

  labels {
    label = "io.portainer.accesscontrol.teams"
    value = "operators"
  }

  ports {
    internal = 6060
    external = 6060
    protocol = "tcp"
  }
  ports {
    internal = 8080
    external = 8080
    protocol = "tcp"
  }

  volumes {
    container_path = "/etc/crowdsec"
    host_path      = "/var/lib/containers/crowdsec/etc"
    read_only      = false
  }
  volumes {
    container_path = "/var/lib/crowdsec/data"
    host_path      = "/var/lib/containers/crowdsec/db"
    read_only      = false
  }
  volumes {
    container_path = "/var/log/traefik"
    host_path      = "/var/lib/containers/traefik/logs"
    read_only      = true
  }
}

resource "docker_container" "adguardhome" {
  provider = docker.internal-net
  name     = "adguardhome"
  image    = docker_image.images["adguard/adguardhome"].image_id
  restart  = "unless-stopped"

  network_mode = "host"

  dynamic "labels" {
    for_each = tomap({
      "io.portainer.accesscontrol.teams"                              = "operators"
      "pangolin.public-resources.dns.name"                            = "AdGuard"
      "pangolin.public-resources.dns.full-domain"                     = "dns0.replo.de"
      "pangolin.public-resources.dns.protocol"                        = "http"
      "pangolin.public-resources.dns.auth.sso-enabled"                = "true"
      "pangolin.public-resources.dns.auth.sso-roles[0]"               = "Member"
      "pangolin.public-resources.dns.auth.auto-login-idp"             = "2"
      "pangolin.public-resources.dns.targets[0].method"               = "http"
      "pangolin.public-resources.dns.targets[0].hostname"             = "172.254.0.1"
      "pangolin.public-resources.dns.targets[0].port"                 = "3000"
      "pangolin.public-resources.dns.targets[0].healthcheck.enabled"  = "true"
      "pangolin.public-resources.dns.targets[0].healthcheck.method"   = "GET"
      "pangolin.public-resources.dns.targets[0].healthcheck.hostname" = "172.254.0.1"
      "pangolin.public-resources.dns.targets[0].healthcheck.path"     = "/"
      "pangolin.public-resources.dns.targets[0].healthcheck.port"     = "3000"
    })
    content {
      label = labels.key
      value = labels.value
    }
  }

  healthcheck {
    test     = ["CMD", "nslookup", "replo.de", "127.0.0.1"]
    interval = "10s"
    timeout  = "10s"
    retries  = 15
  }

  volumes {
    container_path = "/opt/adguardhome/work"
    host_path      = "/var/lib/containers/adguardhome/work"
    read_only      = false
  }
  volumes {
    container_path = "/opt/adguardhome/conf"
    host_path      = "/var/lib/containers/adguardhome/conf"
    read_only      = false
  }
}

resource "docker_container" "adguardhome_sync" {
  provider = docker.internal-net
  name     = "adguardhome_sync"
  image    = docker_image.images["ghcr.io/bakito/adguardhome-sync"].image_id
  restart  = "unless-stopped"

  env = [
    "ORIGIN_URL=http://172.254.0.1:3000",
    "ORIGIN_WEB_URL=https://dns0.replo.de",
    "ORIGIN_USERNAME=russellc",
    "ORIGIN_PASSWORD=${sensitive(data.sops_file.secrets.data["adguardhome.password"])}",
    "REPLICA_URL=http://10.42.20.78:3000",
    "REPLICA_WEB_URL=https://dns1.replo.de",
    "REPLICA_USERNAME=russellc",
    "REPLICA_PASSWORD=${sensitive(data.sops_file.secrets.data["adguardhome.password"])}"
  ]

  networks_advanced {
    name = docker_network.pangolin.name
  }
  networks_advanced {
    name         = docker_network.netsvc.name
    ipv4_address = "172.254.0.6"
  }

  dynamic "labels" {
    for_each = tomap({
      "io.portainer.accesscontrol.teams"                                           = "operators"
      "pangolin.public-resources.adguardhome-sync.name"                            = "AdGuard Sync"
      "pangolin.public-resources.adguardhome-sync.full-domain"                     = "dns-sync.replo.de"
      "pangolin.public-resources.adguardhome-sync.protocol"                        = "http"
      "pangolin.public-resources.adguardhome-sync.auth.sso-enabled"                = "true"
      "pangolin.public-resources.adguardhome-sync.auth.sso-roles[0]"               = "Member"
      "pangolin.public-resources.adguardhome-sync.auth.auto-login-idp"             = "2"
      "pangolin.public-resources.adguardhome-sync.targets[0].method"               = "http"
      "pangolin.public-resources.adguardhome-sync.targets[0].hostname"             = "172.254.0.1"
      "pangolin.public-resources.adguardhome-sync.targets[0].port"                 = "8082"
      "pangolin.public-resources.adguardhome-sync.targets[0].healthcheck.enabled"  = "true"
      "pangolin.public-resources.adguardhome-sync.targets[0].healthcheck.method"   = "GET"
      "pangolin.public-resources.adguardhome-sync.targets[0].healthcheck.hostname" = "172.254.0.1"
      "pangolin.public-resources.adguardhome-sync.targets[0].healthcheck.path"     = "/"
      "pangolin.public-resources.adguardhome-sync.targets[0].healthcheck.port"     = "8082"
    })
    content {
      label = labels.key
      value = labels.value
    }
  }

  ports {
    internal = 8080
    external = 8082
    protocol = "tcp"
  }

  volumes {
    container_path = "/config"
    host_path      = "/var/lib/containers/adguardhome-sync"
    read_only      = false
  }
}

resource "docker_container" "wg-easy" {
  provider = docker.internal-net
  name     = "wg-easy"
  image    = docker_image.images["ghcr.io/wg-easy/wg-easy"].image_id
  restart  = "unless-stopped"

  env = [
    "WG_HOST=replo.de",
    "WG_PORT=51821",
    "PORT=51822",
    "INIT_ENABLED=true",
    "INIT_USERNAME=root",
    "INIT_PASSWORD=${sensitive(data.sops_file.secrets.data["wg_easy.init_password"])}",
    "INIT_HOST=replo.de",
    "INIT_PORT=51821",
    "INIT_DNS=172.254.0.1",
    "INIT_ALLOWED_IPS=172.254.0.0/24",
    "DISABLE_IPV6=true"
  ]

  capabilities {
    add = ["CAP_NET_ADMIN", "CAP_SYS_MODULE"]
  }
  sysctls = {
    "net.ipv4.ip_forward"              = "1"
    "net.ipv4.conf.all.src_valid_mark" = "1"
    "net.ipv6.conf.all.disable_ipv6"   = "0"
    "net.ipv6.conf.all.forwarding"     = "1"
    "net.ipv6.conf.default.forwarding" = "1"
  }

  networks_advanced {
    name         = docker_network.netsvc.name
    ipv4_address = "172.254.0.3"
  }

  dynamic "labels" {
    for_each = tomap({
      "io.portainer.accesscontrol.teams"                             = "operators"
      "pangolin.public-resources.wg.name"                            = "Wireguard"
      "pangolin.public-resources.wg.full-domain"                     = "wg.replo.de"
      "pangolin.public-resources.wg.protocol"                        = "http"
      "pangolin.public-resources.wg.auth.sso-enabled"                = "true"
      "pangolin.public-resources.wg.auth.sso-roles[0]"               = "Member"
      "pangolin.public-resources.wg.auth.auto-login-idp"             = "2"
      "pangolin.public-resources.wg.targets[0].method"               = "http"
      "pangolin.public-resources.wg.targets[0].hostname"             = "172.254.0.3"
      "pangolin.public-resources.wg.targets[0].port"                 = "51822"
      "pangolin.public-resources.wg.targets[0].healthcheck.enabled"  = "true"
      "pangolin.public-resources.wg.targets[0].healthcheck.method"   = "GET"
      "pangolin.public-resources.wg.targets[0].healthcheck.hostname" = "172.254.0.3"
      "pangolin.public-resources.wg.targets[0].healthcheck.path"     = "/"
      "pangolin.public-resources.wg.targets[0].healthcheck.port"     = "51822"
    })
    content {
      label = labels.key
      value = labels.value
    }
  }

  ports {
    internal = 51821
    external = 51821
    protocol = "udp"
  }
  ports {
    internal = 51822
    external = 51822
    protocol = "tcp"
  }

  volumes {
    container_path = "/etc/wireguard"
    host_path      = "/var/lib/containers/wg-easy"
    read_only      = false
  }
  volumes {
    container_path = "/lib/modules"
    host_path      = "/lib/modules"
    read_only      = true
  }
}

resource "docker_container" "pocket_id" {
  provider = docker.internal-net
  name     = "pocket_id"
  image    = docker_image.images["ghcr.io/pocket-id/pocket-id"].image_id
  restart  = "unless-stopped"

  env = [
    "APP_URL=https://id.replo.de",
    "ENCRYPTION_KEY_FILE=/app/enc.key",
    "UI_CONFIG_DISABLED=true",
    "SMTP_HOST=${var.replo_de_smtp_host}",
    "SMTP_PORT=${var.replo_de_smtp_port}",
    "SMTP_USER=${sensitive(data.sops_file.secrets.data["brevo.smtp_username"])}",
    "SMTP_PASSWORD=${sensitive(data.sops_file.secrets.data["brevo.smtp_password"])}",
    "SMTP_FROM=${var.replo_de_smtp_from}",
    "SMTP_TLS=starttls",
    "EMAIL_LOGIN_NOTIFICATION_ENABLED=true",
    "EMAIL_API_KEY_EXPIRATION_ENABLED=true",
    "EMAIL_VERIFICATION_ENABLED=true"
  ]

  dynamic "labels" {
    for_each = tomap({
      "io.portainer.accesscontrol.teams"                             = "operators"
      "pangolin.public-resources.id.name"                            = "Pocket ID"
      "pangolin.public-resources.id.full-domain"                     = "id.replo.de"
      "pangolin.public-resources.id.protocol"                        = "http"
      "pangolin.public-resources.id.auth.sso-enabled"                = "false"
      "pangolin.public-resources.id.targets[0].method"               = "http"
      "pangolin.public-resources.id.targets[0].hostname"             = "172.17.0.1"
      "pangolin.public-resources.id.targets[0].port"                 = "1411"
      "pangolin.public-resources.id.targets[0].healthcheck.enabled"  = "true"
      "pangolin.public-resources.id.targets[0].healthcheck.method"   = "GET"
      "pangolin.public-resources.id.targets[0].healthcheck.hostname" = "172.17.0.1"
      "pangolin.public-resources.id.targets[0].healthcheck.path"     = "/"
      "pangolin.public-resources.id.targets[0].healthcheck.port"     = "1411"
    })
    content {
      label = labels.key
      value = labels.value
    }
  }

  volumes {
    container_path = "/app/enc.key"
    host_path      = "/var/lib/containers/pocket-id/enc.key"
    read_only      = true
  }
  volumes {
    container_path = "/app/data"
    host_path      = "/var/lib/containers/pocket-id/data"
    read_only      = false
  }

  ports {
    internal = 1411
    external = 1411
    protocol = "tcp"
  }

  healthcheck {
    test         = ["CMD", "/app/pocket-id", "healthcheck"]
    interval     = "1m30s"
    start_period = "10s"
    timeout      = "5s"
    retries      = 2
  }
}

resource "docker_container" "beszel" {
  provider = docker.internal-net
  name     = "beszel"
  image    = docker_image.images["henrygd/beszel"].image_id
  restart  = "unless-stopped"

  env = [
    "APP_URL=https://up.replo.de"
  ]

  dynamic "labels" {
    for_each = tomap({
      "io.portainer.accesscontrol.teams"                             = "operators"
      "pangolin.public-resources.up.name"                            = "Beszel"
      "pangolin.public-resources.up.full-domain"                     = "up.replo.de"
      "pangolin.public-resources.up.protocol"                        = "http"
      "pangolin.public-resources.up.auth.sso-enabled"                = "true"
      "pangolin.public-resources.up.auth.sso-roles[0]"               = "Member"
      "pangolin.public-resources.up.auth.auto-login-idp"             = "2"
      "pangolin.public-resources.up.targets[0].method"               = "http"
      "pangolin.public-resources.up.targets[0].hostname"             = "172.17.0.1"
      "pangolin.public-resources.up.targets[0].port"                 = "8090"
      "pangolin.public-resources.up.targets[0].healthcheck.enabled"  = "true"
      "pangolin.public-resources.up.targets[0].healthcheck.method"   = "GET"
      "pangolin.public-resources.up.targets[0].healthcheck.hostname" = "172.17.0.1"
      "pangolin.public-resources.up.targets[0].healthcheck.path"     = "/"
      "pangolin.public-resources.up.targets[0].healthcheck.port"     = "8090"
      "pangolin.public-resources.up.rules[0].action"                 = "allow"
      "pangolin.public-resources.up.rules[0].match"                  = "path"
      "pangolin.public-resources.up.rules[0].value"                  = "/api/*"
    })
    content {
      label = labels.key
      value = labels.value
    }
  }

  volumes {
    container_path = "/beszel_data"
    host_path      = "/var/lib/containers/beszel"
    read_only      = false
  }

  ports {
    internal = 8090
    external = 8090
    protocol = "tcp"
  }
}

resource "docker_container" "beszel_agent" {
  provider = docker.internal-net
  name     = "beszel_agent"
  image    = docker_image.images["henrygd/beszel-agent"].image_id
  restart  = "unless-stopped"

  labels {
    label = "io.portainer.accesscontrol.teams"
    value = "operators"
  }

  network_mode = "host"

  env = [
    "HUB_URL=https://up.replo.de",
    "KEY=${sensitive(data.sops_file.secrets.data["beszel.pub_key"])}",
    "TOKEN=${sensitive(data.sops_file.secrets.data["beszel.hcloud_token"])}",
    "LISTEN=45876",
  ]

  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
    read_only      = true
  }
  volumes {
    container_path = "/extra-filesystems/sdb__internal-net-vol"
    host_path      = "/var/lib/containers"
    read_only      = true
  }
}

resource "docker_container" "diun" {
  provider = docker.internal-net
  name     = "diun"
  image    = docker_image.images["crazymax/diun"].image_id
  command  = ["serve"]
  restart  = "unless-stopped"
  hostname = "hcloud"

  labels {
    label = "io.portainer.accesscontrol.teams"
    value = "operators"
  }

  env = [
    "TZ=${local.tz}",
    "DIUN_WATCH_WORKERS=20",
    "DIUN_WATCH_SCHEDULE=0 */6 * * *",
    "DIUN_WATCH_JITTER=30s",
    "DIUN_WATCH_FIRSTCHECKNOTIF=true",
    "DIUN_PROVIDERS_DOCKER=true",
    "DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT=true",
    "DIUN_DEFAULTS_WATCHREPO=true",
    "DIUN_DEFAULTS_MAXTAGS=1",
    "DIUN_DEFAULTS_SORTTAGS=semver",
    "DIUN_DEFAULTS_INCLUDETAGS=${local.diun_include_pattern}",
    "DIUN_DEFAULTS_EXCLUDETAGS=${local.diun_exclude_pattern}",
    "DIUN_NOTIF_MAIL_HOST=${var.replo_de_smtp_host}",
    "DIUN_NOTIF_MAIL_PORT=${var.replo_de_smtp_port}",
    "DIUN_NOTIF_MAIL_SSL=false",
    "DIUN_NOTIF_MAIL_USERNAME=${sensitive(data.sops_file.secrets.data["brevo.smtp_username"])}",
    "DIUN_NOTIF_MAIL_PASSWORD=${sensitive(data.sops_file.secrets.data["brevo.smtp_password"])}",
    "DIUN_NOTIF_MAIL_FROM=${var.replo_de_smtp_from}",
    "DIUN_NOTIF_MAIL_TO=${var.replo_de_smtp_to}",
    "DIUN_NOTIF_MAIL_TEMPLATETITLE=${local.diun_mail_template_title}",
    "DIUN_NOTIF_MAIL_TEMPLATEBODY=${local.diun_mail_template_body}",
  ]

  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
    read_only      = true
  }
  volumes {
    container_path = "/data"
    host_path      = "/var/lib/containers/diun"
    read_only      = false
  }
}

resource "docker_container" "portainer" {
  provider = docker.internal-net
  name     = "portainer"
  image    = docker_image.images["portainer/portainer-ce"].image_id
  restart  = "unless-stopped"

  dynamic "labels" {
    for_each = tomap({
      "io.portainer.accesscontrol.teams"                                    = "operators"
      "pangolin.public-resources.portainer.name"                            = "Portainer"
      "pangolin.public-resources.portainer.full-domain"                     = "port.replo.de"
      "pangolin.public-resources.portainer.protocol"                        = "http"
      "pangolin.public-resources.portainer.auth.sso-enabled"                = "true"
      "pangolin.public-resources.portainer.auth.sso-roles[0]"               = "Member"
      "pangolin.public-resources.portainer.auth.auto-login-idp"             = "2"
      "pangolin.public-resources.portainer.targets[0].method"               = "http"
      "pangolin.public-resources.portainer.targets[0].hostname"             = "172.17.0.1"
      "pangolin.public-resources.portainer.targets[0].port"                 = "9001"
      "pangolin.public-resources.portainer.targets[0].healthcheck.enabled"  = "true"
      "pangolin.public-resources.portainer.targets[0].healthcheck.method"   = "GET"
      "pangolin.public-resources.portainer.targets[0].healthcheck.hostname" = "172.17.0.1"
      "pangolin.public-resources.portainer.targets[0].healthcheck.path"     = "/"
      "pangolin.public-resources.portainer.targets[0].healthcheck.port"     = "9001"
      "pangolin.public-resources.portainer.rules[0].action"                 = "allow"
      "pangolin.public-resources.portainer.rules[0].match"                  = "path"
      "pangolin.public-resources.portainer.rules[0].value"                  = "/api/*"
    })
    content {
      label = labels.key
      value = labels.value
    }
  }

  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
    read_only      = true
  }
  volumes {
    container_path = "/data"
    host_path      = "/var/lib/containers/portainer"
    read_only      = false
  }

  ports {
    internal = 9000
    external = 9001
    protocol = "tcp"
  }
  ports {
    internal = 8000
    external = 8000
    protocol = "tcp"
  }
}

resource "docker_container" "dozzle" {
  provider = docker.internal-net
  name     = "dozzle"
  image    = docker_image.images["amir20/dozzle"].image_id
  restart  = "unless-stopped"
  hostname = "hcloud"

  networks_advanced {
    name         = docker_network.netsvc.name
    ipv4_address = "172.254.0.7"
  }

  dynamic "labels" {
    for_each = tomap({
      "io.portainer.accesscontrol.teams" = "operators"
    })
    content {
      label = labels.key
      value = labels.value
    }
  }

  env = [
    "DOZZLE_ADDR=:9090",
    "DOZZLE_REMOTE_AGENT=10.42.20.78:7007",
    "DOZZLE_ENABLE_ACTIONS=true",
    "DOZZLE_AUTH_PROVIDER=forward-proxy",
    "DOZZLE_AUTH_HEADER_USER=X-Forwarded-User",
    "DOZZLE_AUTH_HEADER_EMAIL=X-Forwarded-Email",
    "DOZZLE_AUTH_HEADER_NAME=X-Forwarded-Preferred-Username",
    "DOZZLE_NO_ANALYTICS=true"
  ]

  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
    read_only      = true
  }
  volumes {
    container_path = "/data"
    host_path      = "/var/lib/containers/dozzle"
    read_only      = false
  }
}

resource "docker_container" "dozzle_oauth_proxy" {
  provider = docker.internal-net
  name     = "dozzle_oauth_proxy"
  image    = docker_image.images["quay.io/oauth2-proxy/oauth2-proxy"].image_id
  restart  = "unless-stopped"
  hostname = "hcloud"

  networks_advanced {
    name         = docker_network.netsvc.name
    ipv4_address = "172.254.0.8"
  }

  dynamic "labels" {
    for_each = tomap({
      "io.portainer.accesscontrol.teams"                                 = "operators",
      "pangolin.public-resources.dozzle.name"                            = "Dozzle"
      "pangolin.public-resources.dozzle.full-domain"                     = "logs.replo.de"
      "pangolin.public-resources.dozzle.protocol"                        = "http"
      "pangolin.public-resources.dozzle.auth.sso-enabled"                = "true"
      "pangolin.public-resources.dozzle.auth.sso-roles[0]"               = "Member"
      "pangolin.public-resources.dozzle.auth.auto-login-idp"             = "2"
      "pangolin.public-resources.dozzle.targets[0].method"               = "http"
      "pangolin.public-resources.dozzle.targets[0].hostname"             = "172.17.0.1"
      "pangolin.public-resources.dozzle.targets[0].port"                 = "9090"
      "pangolin.public-resources.dozzle.targets[0].healthcheck.enabled"  = "true"
      "pangolin.public-resources.dozzle.targets[0].healthcheck.method"   = "GET"
      "pangolin.public-resources.dozzle.targets[0].healthcheck.hostname" = "172.254.0.7"
      "pangolin.public-resources.dozzle.targets[0].healthcheck.path"     = "/healthcheck"
      "pangolin.public-resources.dozzle.targets[0].healthcheck.port"     = "9090"
      "pangolin.public-resources.dozzle.rules[0].action"                 = "allow"
      "pangolin.public-resources.dozzle.rules[0].match"                  = "path"
      "pangolin.public-resources.dozzle.rules[0].value"                  = "/api/*"
    })
    content {
      label = labels.key
      value = labels.value
    }
  }

  env = [
    "OAUTH2_PROXY_CLIENT_ID=${sensitive(data.sops_file.secrets.data["dozzle.oauth_client_id"])}",
    "OAUTH2_PROXY_CLIENT_SECRET=${sensitive(data.sops_file.secrets.data["dozzle.oauth_client_secret"])}",
    "OAUTH2_PROXY_COOKIE_SECRET=${sensitive(data.sops_file.secrets.data["dozzle.oauth_cookie_secret"])}",
    "OAUTH2_PROXY_UPSTREAMS=http://172.254.0.7:9090",
    "OAUTH2_PROXY_CODE_CHALLENGE_METHOD=S256",
    "OAUTH2_PROXY_COOKIE_EXPIRE=0",
    "OAUTH2_PROXY_COOKIE_NAME=__Host-oauth2-proxy",
    "OAUTH2_PROXY_COOKIE_SECURE=true",
    "OAUTH2_PROXY_EMAIL_DOMAINS=*",
    "OAUTH2_PROXY_INSECURE_OIDC_ALLOW_UNVERIFIED_EMAIL=true",
    "OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4180",
    "OAUTH2_PROXY_OIDC_ISSUER_URL=https://id.replo.de",
    "OAUTH2_PROXY_PROVIDER_DISPLAY_NAME=Pocket ID",
    "OAUTH2_PROXY_PROVIDER=oidc",
    "OAUTH2_PROXY_REVERSE_PROXY=true",
    "OAUTH2_PROXY_SCOPE=openid email profile groups",
    "OAUTH2_PROXY_TRUSTED_PROXY_IPS=172.254.0.0/24",
    "OAUTH2_PROXY_BANNER=-",
    "OAUTH2_PROXY_CUSTOM_SIGN_IN_LOGO=-",
    "OAUTH2_PROXY_FOOTER=-",
    "OAUTH2_PROXY_REQUEST_LOGGING=false"
  ]

  ports {
    internal = 4180
    external = 9090
    protocol = "tcp"
  }
}

resource "docker_container" "caddy" {
  provider = docker.internal-net
  name     = "caddy"
  image    = docker_image.images["caddy"].image_id
  restart  = "unless-stopped"

  dynamic "labels" {
    for_each = tomap({
      "io.portainer.accesscontrol.teams"                                = "operators"
      "pangolin.public-resources.caddy.name"                            = "Caddy"
      "pangolin.public-resources.caddy.full-domain"                     = "replo.de"
      "pangolin.public-resources.caddy.protocol"                        = "http"
      "pangolin.public-resources.caddy.auth.sso-enabled"                = "false"
      "pangolin.public-resources.caddy.targets[0].method"               = "http"
      "pangolin.public-resources.caddy.targets[0].hostname"             = "172.17.0.1"
      "pangolin.public-resources.caddy.targets[0].port"                 = "8081"
      "pangolin.public-resources.caddy.targets[0].healthcheck.enabled"  = "true"
      "pangolin.public-resources.caddy.targets[0].healthcheck.method"   = "GET"
      "pangolin.public-resources.caddy.targets[0].healthcheck.hostname" = "172.17.0.1"
      "pangolin.public-resources.caddy.targets[0].healthcheck.path"     = "/"
      "pangolin.public-resources.caddy.targets[0].healthcheck.port"     = "8081"
    })
    content {
      label = labels.key
      value = labels.value
    }
  }

  volumes {
    container_path = "/usr/share/caddy"
    host_path      = "/var/lib/containers/caddy/srv"
    read_only      = true
  }

  ports {
    internal = 80
    external = 8081
    protocol = "tcp"
  }
}
