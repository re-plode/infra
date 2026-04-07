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
    port       = "53"
    source_ips = local.all_ips
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "53"
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
    add = ["NET_ADMIN", "SYS_MODULE"]
  }

  volumes {
    container_path = "/var/config"
    host_path      = "/var/lib/containers/gerbil/config"
  }

  # Ports
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

  networks_advanced {
    name = docker_network.pangolin.name
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
  network_mode = "container:${docker_container.gerbil.name}"

  command = ["--configFile=/etc/traefik/traefik_config.yml"]

  volumes {
    container_path = "/etc/traefik"
    host_path      = "/var/lib/containers/traefik/etc"
    read_only      = true
  }
  volumes {
    container_path = "/letsencrypt"
    host_path      = "/var/lib/containers/traefik/letsencrypt"
  }
  volumes {
    container_path = "/var/log/traefik"
    host_path      = "/var/lib/containers/traefik/logs"
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

  volumes {
    container_path = "/opt/adguardhome/work"
    host_path      = "/var/lib/containers/adguardhome/work"
  }
  volumes {
    container_path = "/opt/adguardhome/conf"
    host_path      = "/var/lib/containers/adguardhome/conf"
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
