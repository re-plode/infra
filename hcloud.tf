resource "hcloud_ssh_key" "fedora" {
  name       = "russellc@fedora"
  public_key = file("config/ssh/id_ed25519_fedora.pub")
}
resource "hcloud_ssh_key" "ipadpro" {
  name       = "russellc@ipadpro"
  public_key = file("config/ssh/id_ed25519_ipadpro.pub")
}
resource "hcloud_ssh_key" "github" {
  name       = "russellc@github"
  public_key = file("config/ssh/id_ed25519_github.pub")
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
}

resource "hcloud_server" "internal_net" {
  name        = "internal-net"
  image       = "docker-ce"
  server_type = "cax11"
  location    = "nbg1"
  backups     = false

  user_data = file("config/cloudinit.yml")

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  ssh_keys = [
    hcloud_ssh_key.fedora.id,
    hcloud_ssh_key.ipadpro.id,
    hcloud_ssh_key.github.id
  ]
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

resource "docker_image" "pangolin" {
  provider = docker.internal-net
  name     = "fosrl/pangolin:latest"
}
resource "docker_container" "pangolin" {
  provider = docker.internal-net
  name     = "pangolin"
  image    = docker_image.pangolin.image_id
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
}

resource "docker_image" "gerbil" {
  provider = docker.internal-net
  name     = "fosrl/gerbil:latest"
}
resource "docker_container" "gerbil" {
  provider = docker.internal-net
  name     = "gerbil"
  image    = docker_image.gerbil.image_id
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

resource "docker_image" "traefik" {
  provider = docker.internal-net
  name     = "traefik:v3.6"
}
resource "docker_container" "traefik" {
  provider     = docker.internal-net
  name         = "traefik"
  image        = docker_image.traefik.image_id
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
}

resource "docker_image" "adguardhome" {
  provider = docker.internal-net
  name     = "adguard/adguardhome:latest"
}
resource "docker_container" "adguardhome" {
  provider = docker.internal-net
  name     = "adguardhome"
  image    = docker_image.adguardhome.image_id
  restart  = "unless-stopped"

  network_mode = "host"

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

  ports {
    internal = 53
    external = 53
    protocol = "tcp"
  }
  ports {
    internal = 53
    external = 53
    protocol = "udp"
  }
  # ports {
  #   internal = 67
  #   external = 67
  #   protocol = "udp"
  # }
  # ports {
  #   internal = 68
  #   external = 68
  #   protocol = "tcp"
  # }
  # ports {
  #   internal = 68
  #   external = 68
  #   protocol = "udp"
  # }
  ports {
    internal = 3000
    external = 3000
    protocol = "tcp"
  }
}

resource "docker_image" "newt" {
  provider = docker.internal-net
  name     = "fosrl/newt:latest"
}
resource "docker_container" "newt" {
  provider = docker.internal-net
  name     = "newt"
  image    = docker_image.newt.image_id
  restart  = "unless-stopped"

  env = [
    "PANGOLIN_ENDPOINT=https://replo.de",
    "NEWT_ID=${var.hcloud_newt_id}",
    "NEWT_SECRET=${var.hcloud_newt_secret}"
  ]

  networks_advanced {
    name         = docker_network.netsvc.name
    ipv4_address = "172.254.0.5"
  }
}

resource "docker_image" "wg-easy" {
  provider = docker.internal-net
  name     = "ghcr.io/wg-easy/wg-easy:15"
}
resource "docker_container" "wg-easy" {
  provider = docker.internal-net
  name     = "wg-easy"
  image    = docker_image.wg-easy.image_id
  restart  = "unless-stopped"

  env = [
    "WG_HOST=replo.de",
    "WG_PORT=51821",
    "PORT=51822",
    "INIT_ENABLED=true",
    "INIT_USERNAME=root",
    "INIT_PASSWORD=${var.wg_easy_init_password}",
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
