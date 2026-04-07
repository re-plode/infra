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
  alias = "internal-net"
  host  = "ssh://root@replo.de"
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
