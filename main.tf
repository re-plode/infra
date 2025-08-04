terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    # synology = {
    #   source  = "synology-community/synology"
    #   version = "~> 0.4"
    # }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

# provider "synology" {
#   skip_cert_check = true
# }

resource "hcloud_ssh_key" "fedora" {
  name       = "russellc@fedora"
  public_key = file("config/ssh/id_ed25519_fedora.pub")
}
resource "hcloud_ssh_key" "ipadpro" {
  name       = "russellc@ipadpro"
  public_key = file("config/ssh/id_ed25519_ipadpro.pub")
}

data "hcloud_image" "coreos_snapshot" {
  with_selector = "os_family=fedora,os_flavor=coreos,os_arch=x86_64"
  most_recent   = true
}

data "external" "ignition" {
  program = ["./bin/butane.sh", "--files-dir", ".", "coreos/internal-net.bu"]
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
    port       = "5022"
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
  name        = "internal-net-coreos-2gb-nbg1-1"
  image       = data.hcloud_image.coreos_snapshot.id
  server_type = "cpx11"
  location    = "nbg1"
  backups     = false
  user_data   = data.external.ignition.result.ign
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
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

resource "hcloud_firewall_attachment" "internal_net_firewall_attachment" {
  firewall_id = hcloud_firewall.internal_net_firewall.id
  server_ids  = [hcloud_server.internal_net.id]
}

resource "hcloud_volume_attachment" "internal_net_vol_attachment" {
  volume_id = hcloud_volume.internal_net_vol.id
  server_id = hcloud_server.internal_net.id
  automount = true
}

# resource "synology_container_project" "nginx" {
#   name = "nginx"
#   run  = true
#   services = {
#     nginx = {
#       name           = "nginx"
#       container_name = "nginx"
#       user           = "root"
#       restart        = "unless-stopped"
#       replicas       = 1
#       image          = "nginx:latest"
#     }
#   }
# }

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
