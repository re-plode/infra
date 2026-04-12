terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    synology = {
      source = "synology-community/synology"
      # Version 0.6.10 fails to check response
      version = "<= 0.6.9"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.0.0"
    }
    mailgun = {
      source  = "wgebis/mailgun"
      version = "~> 0.9.0"
    }
  }

  backend "s3" {
    bucket = "infra"
    key    = "terraform.tfstate"

    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true

    access_key = var.cloudflare_r2_key
    secret_key = var.cloudflare_r2_secret

    endpoints = { s3 = var.cloudflare_r2_endpoint }
  }
}

provider "mailgun" {
  api_key = var.mailgun_api_key
}

provider "synology" {
  host            = "https://${var.dsm_host}:5001"
  user            = var.dsm_user
  password        = var.dsm_password
  skip_cert_check = true
  session_cache = {
    mode = "memory"
  }
}

provider "docker" {
  alias = "internal-net"
  host  = "ssh://root@${hcloud_server.internal_net.ipv4_address}"
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
