resource "hcloud_ssh_key" "ssh_keys" {
  for_each = tomap({
    "russellc@fedora"  = "config/ssh/id_ed25519_fedora.pub"
    "russellc@ipadpro" = "config/ssh/id_ed25519_ipadpro.pub"
    "russellc@github"  = "config/ssh/id_ed25519_github.pub"
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
    ipv6_enabled = true
  }

  ssh_keys = [
    hcloud_ssh_key.ssh_keys["russellc@fedora"].id,
    hcloud_ssh_key.ssh_keys["russellc@ipadpro"].id,
    hcloud_ssh_key.ssh_keys["russellc@github"].id
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
  name              = "internal-net-ip"
  type              = "ipv4"
  assignee_id       = hcloud_server.internal_net.id
  assignee_type     = "server"
  delete_protection = true
  auto_delete       = false
}

resource "hcloud_firewall_attachment" "internal_net_firewall_attachment" {
  firewall_id = hcloud_firewall.internal_net_firewall.id
  server_ids  = [hcloud_server.internal_net.id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_volume_attachment" "internal_net_vol_attachment" {
  volume_id = hcloud_volume.internal_net_vol.id
  server_id = hcloud_server.internal_net.id
  automount = true

  lifecycle {
    prevent_destroy = true
  }
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
resource "docker_network" "authentik" {
  provider = docker.internal-net
  name     = "authentik"
  driver   = "bridge"
}

resource "docker_image" "images" {
  for_each = tomap({
    "fosrl/pangolin"             = "1.17.0"
    "fosrl/gerbil"               = "1.3.1"
    "traefik"                    = "3.6.13"
    "fosrl/newt"                 = "1.11.0"
    "adguard/adguardhome"        = "v0.107.73"
    "ghcr.io/wg-easy/wg-easy"    = "15.2.2"
    "postgres"                   = "16-alpine"
    "ghcr.io/goauthentik/server" = "2026.2.2"
  })
  provider = docker.internal-net
  name     = "${each.key}:${each.value}"
}

resource "docker_container" "pangolin" {
  provider = docker.internal-net
  name     = "pangolin"
  image    = docker_image.images["fosrl/pangolin"].image_id
  restart  = "unless-stopped"

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

  lifecycle {
    prevent_destroy = true
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

  capabilities {
    add = ["CAP_NET_ADMIN", "CAP_SYS_MODULE"]
  }

  networks_advanced {
    name = docker_network.pangolin.name
  }
  networks_advanced {
    name = docker_network.authentik.name
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

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "traefik" {
  provider     = docker.internal-net
  name         = "traefik"
  image        = docker_image.images["traefik"].image_id
  restart      = "unless-stopped"
  network_mode = "container:${docker_container.gerbil.id}"

  command = ["--configFile=/etc/traefik/traefik_config.yml"]

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

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "newt" {
  provider = docker.internal-net
  name     = "newt"
  image    = docker_image.images["fosrl/newt"].image_id
  restart  = "unless-stopped"

  env = [
    "PANGOLIN_ENDPOINT=https://replo.de",
    "NEWT_ID=${data.sops_file.secrets.data["pangolin.hcloud_newt_id"]}",
    "NEWT_SECRET=${data.sops_file.secrets.data["pangolin.hcloud_newt_secret"]}",
    "DOCKER_SOCKET=/var/run/docker.sock"
  ]

  networks_advanced {
    name         = docker_network.netsvc.name
    ipv4_address = "172.254.0.5"
  }

  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
    read_only      = true
  }

  lifecycle {
    prevent_destroy = true
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
      "pangolin.public-resources.dns.name"                            = "AdGuard"
      "pangolin.public-resources.dns.full-domain"                     = "dns.replo.de"
      "pangolin.public-resources.dns.protocol"                        = "http"
      "pangolin.public-resources.dns.auth.sso-enabled"                = "true"
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

  lifecycle {
    prevent_destroy = true
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
    "INIT_PASSWORD=${data.sops_file.secrets.data["wg_easy.init_password"]}",
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

  labels {
    label = "pangolin.public-resources.wg.name"
    value = "Wireguard"
  }
  labels {
    label = "pangolin.public-resources.wg.full-domain"
    value = "wg.replo.de"
  }
  labels {
    label = "pangolin.public-resources.wg.protocol"
    value = "http"
  }
  labels {
    label = "pangolin.public-resources.wg.auth.sso-enabled"
    value = "true"
  }
  labels {
    label = "pangolin.public-resources.wg.targets[0].method"
    value = "http"
  }
  labels {
    label = "pangolin.public-resources.wg.targets[0].hostname"
    value = "172.254.0.3"
  }
  labels {
    label = "pangolin.public-resources.wg.targets[0].port"
    value = "51822"
  }
  labels {
    label = "pangolin.public-resources.wg.targets[0].healthcheck.enabled"
    value = "true"
  }
  labels {
    label = "pangolin.public-resources.wg.targets[0].healthcheck.method"
    value = "GET"
  }
  labels {
    label = "pangolin.public-resources.wg.targets[0].healthcheck.hostname"
    value = "172.254.0.3"
  }
  labels {
    label = "pangolin.public-resources.wg.targets[0].healthcheck.path"
    value = "/"
  }
  labels {
    label = "pangolin.public-resources.wg.targets[0].healthcheck.port"
    value = "51822"
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

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "authentik_pg" {
  provider = docker.internal-net
  name     = "authentik_pg"
  image    = docker_image.images["postgres"].image_id
  restart  = "unless-stopped"

  networks_advanced {
    name = docker_network.authentik.name
  }

  env = [
    "POSTGRES_DB=authentik",
    "POSTGRES_PASSWORD=${data.sops_file.secrets.data["authentik.database_password"]}",
    "POSTGRES_USER=authentik"
  ]

  volumes {
    container_path = "/var/lib/postgresql/data"
    host_path      = "/var/lib/containers/authentik_pg/data"
    read_only      = false
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -d $POSTGRES_DB -U $POSTGRES_USER"]
    interval     = "30s"
    start_period = "20s"
    timeout      = "5s"
    retries      = 5
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "authentik_srv" {
  provider = docker.internal-net
  name     = "authentik_srv"
  image    = docker_image.images["ghcr.io/goauthentik/server"].image_id
  command  = ["server"]
  restart  = "unless-stopped"

  shm_size = 512

  networks_advanced {
    name = docker_network.authentik.name
  }

  dynamic "labels" {
    for_each = tomap({
      "pangolin.public-resources.ak.name"                            = "Authentik"
      "pangolin.public-resources.ak.full-domain"                     = "ak.replo.de"
      "pangolin.public-resources.ak.protocol"                        = "http"
      "pangolin.public-resources.ak.auth.sso-enabled"                = "false"
      "pangolin.public-resources.ak.targets[0].method"               = "http"
      "pangolin.public-resources.ak.targets[0].hostname"             = "172.17.0.1"
      "pangolin.public-resources.ak.targets[0].port"                 = "9000"
      "pangolin.public-resources.ak.targets[0].healthcheck.enabled"  = "true"
      "pangolin.public-resources.ak.targets[0].healthcheck.method"   = "GET"
      "pangolin.public-resources.ak.targets[0].healthcheck.hostname" = "172.17.0.1"
      "pangolin.public-resources.ak.targets[0].healthcheck.path"     = "/"
      "pangolin.public-resources.ak.targets[0].healthcheck.port"     = "9000"
    })
    content {
      label = labels.key
      value = labels.value
    }
  }

  env = [
    "AUTHENTIK_POSTGRESQL__HOST=authentik_pg",
    "AUTHENTIK_POSTGRESQL__NAME=authentik",
    "AUTHENTIK_POSTGRESQL__PASSWORD=${data.sops_file.secrets.data["authentik.database_password"]}",
    "AUTHENTIK_POSTGRESQL__USER=authentik",
    "AUTHENTIK_SECRET_KEY=${data.sops_file.secrets.data["authentik.secret_key"]}"
  ]

  ports {
    internal = 9000
    external = 9000
    protocol = "tcp"
  }
  ports {
    internal = 9443
    external = 9443
    protocol = "tcp"
  }

  volumes {
    container_path = "/data"
    host_path      = "/var/lib/containers/authentik/data"
    read_only      = false
  }
  volumes {
    container_path = "/templates"
    host_path      = "/var/lib/containers/authentik/templates"
    read_only      = false
  }

  depends_on = [docker_container.authentik_pg]

  lifecycle {
    prevent_destroy = true
  }
}

resource "docker_container" "authentik_wrk" {
  provider = docker.internal-net
  name     = "authentik_wrk"
  image    = docker_image.images["ghcr.io/goauthentik/server"].image_id
  command  = ["worker"]
  restart  = "unless-stopped"

  user     = "root"
  shm_size = 512

  networks_advanced {
    name = docker_network.authentik.name
  }

  env = [
    "AUTHENTIK_POSTGRESQL__HOST=authentik_pg",
    "AUTHENTIK_POSTGRESQL__NAME=authentik",
    "AUTHENTIK_POSTGRESQL__PASSWORD=${data.sops_file.secrets.data["authentik.database_password"]}",
    "AUTHENTIK_POSTGRESQL__USER=authentik",
    "AUTHENTIK_SECRET_KEY=${data.sops_file.secrets.data["authentik.secret_key"]}"
  ]

  volumes {
    container_path = "/data"
    host_path      = "/var/lib/containers/authentik/data"
    read_only      = false
  }
  volumes {
    container_path = "/templates"
    host_path      = "/var/lib/containers/authentik/templates"
    read_only      = false
  }
  volumes {
    container_path = "/certs"
    host_path      = "/var/lib/containers/authentik/certs"
    read_only      = false
  }
  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
    read_only      = true
  }

  depends_on = [docker_container.authentik_pg]

  lifecycle {
    prevent_destroy = true
  }
}
