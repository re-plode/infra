terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    mailgun = {
      source  = "wgebis/mailgun"
      version = "~> 0.7.7"
    }
  }
}

# Hetzner
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

resource "hcloud_volume_attachment" "internal_net_vol_attachment" {
  volume_id = hcloud_volume.internal_net_vol.id
  server_id = hcloud_server.internal_net.id
  automount = true
}

# Mailgun
provider "mailgun" {
  api_key = var.mailgun_api_key
}

resource "mailgun_domain" "replode" {
  name          = "replo.de"
  region        = "eu"
  spam_action   = "disabled"
  smtp_password = var.mailgun_smtp_password
  dkim_key_size = 1024
}
