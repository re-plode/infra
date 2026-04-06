terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    synology = {
      source  = "synology-community/synology"
      version = "~> 0.5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.0.0"
    }
  }
}

provider "synology" {
  host            = var.dsm_host
  user            = var.dsm_user
  password        = var.dsm_password
  skip_cert_check = true
}

provider "docker" {
  host = "ssh://root@replo.de"
  ssh_opts = [
    "-i",
    "~/.ssh/${var.ssh_identity}",
    "-o",
    "StrictHostKeyChecking=no",
    "-o",
    "UserKnownHostsFile=/dev/null"
  ]
  disable_docker_daemon_check = true
}

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

resource "synology_container_project" "nginx" {
  name = "nginx"
  run  = true
  services = {
    nginx = {
      name           = "nginx"
      container_name = "nginx"
      user           = "root"
      restart        = "unless-stopped"
      replicas       = 1
      image          = "nginx:latest"
    }
  }
}

resource "cloudflare_dns_record" "replo_de_dns_a_record" {
  zone_id = "866a9591267d97262251a392a85dbd7c"
  content = hcloud_server.internal_net.ipv4_address
  name    = "@"
  proxied = false
  ttl     = 1
  type    = "A"
}
resource "cloudflare_dns_record" "wildcard_replo_de_dns_cname_record" {
  zone_id = "866a9591267d97262251a392a85dbd7c"
  content = "@"
  name    = "*"
  proxied = false
  ttl     = 1
  type    = "CNAME"
}

# Network equivalent to `networks: default: name: pangolin`
resource "docker_network" "pangolin" {
  name   = "pangolin"
  driver = "bridge"
}

# Pull images
resource "docker_image" "pangolin" {
  name = "fosrl/pangolin:latest"
}

resource "docker_image" "gerbil" {
  name = "fosrl/gerbil:latest"
}

resource "docker_image" "traefik" {
  name = "traefik:v3.6"
}

# Pangolin container with healthcheck and config volume
resource "docker_container" "pangolin" {
  name    = "pangolin"
  image   = docker_image.pangolin.image_id
  restart = "unless-stopped"

  # mount config volume into /app/config as in compose
  volumes {
    container_path = "/app/config"
    host_path      = "/var/lib/containers/pangolin/config"
  }

  # healthcheck
  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:3001/api/v1/"]
    interval = "10s"
    timeout  = "10s"
    retries  = 15
  }

  networks_advanced {
    name = docker_network.pangolin.name
  }
}

# Gerbil container that depends on pangolin (Terraform depends_on ensures create order,
# but note it doesn't enforce Docker service health status)
resource "docker_container" "gerbil" {
  name    = "gerbil"
  image   = docker_image.gerbil.image_id
  restart = "unless-stopped"

  # command on container (list form)
  command = [
    "--reachableAt=http://gerbil:3004",
    "--generateAndSaveKeyTo=/var/config/key",
    "--remoteConfig=http://pangolin:3001/api/v1/"
  ]

  # mount same config volume at /var/config
  volumes {
    container_path = "/var/config"
    host_path      = "/var/lib/containers/gerbil/config"
  }

  # Capabilities
  capabilities {
    add = ["NET_ADMIN", "SYS_MODULE"]
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

  # ensure gerbil is created after pangolin (note: this doesn't wait for pangolin HEALTHY state)
  depends_on = [docker_container.pangolin]
}

# Traefik: uses the network namespace of gerbil (network_mode: service:gerbil)
resource "docker_container" "traefik" {
  name    = "traefik"
  image   = docker_image.traefik.image_id
  restart = "unless-stopped"

  # Use the service network mode so Traefik binds ports on gerbil's network namespace.
  # This replicates Compose's `network_mode: service:gerbil`.
  # network_mode = "container:${docker_container.gerbil.name}"

  networks_advanced {
    name = docker_network.pangolin.name
  }

  command = [
    "--configFile=/etc/traefik/traefik_config.yml"
  ]

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

  # Make sure Traefik is created after services it depends on
  depends_on = [docker_container.pangolin, docker_container.gerbil]
}
