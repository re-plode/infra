variable "ssh_identity" {
  type = string
}

variable "dsm_host" {
  type = string
}

variable "tf_passphrase" {
  default   = "changeme!"
  sensitive = true
}

variable "replo_de_smtp_host" {
  default = "smtp-relay.brevo.com"
  type    = string
}
variable "replo_de_smtp_port" {
  default = 587
  type    = number
}
variable "replo_de_smtp_from" {
  default = "noreply@replo.de"
  type    = string
}
variable "replo_de_smtp_to" {
  default = "root@replo.de"
  type    = string
}

locals {
  s920p_media_uid = "1027"
  s920p_media_gid = "65536"

  diun_include_pattern           = "^v?\\d+\\.\\d+(\\.\\d+)?$"
  diun_exclude_pattern           = "^\\w+$"
  cloudflare_rcheung_com_zone_id = "e4edb9787160b70638898ebfd69c0fd0"
  cloudflare_replo_de_zone_id    = "866a9591267d97262251a392a85dbd7c"

  tz = "Europe/Berlin"

  cloudflare_ips = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
    "2400:cb00::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2405:b500::/32",
    "2405:8100::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32"
  ]
  all_ips = [
    "0.0.0.0/0",
    "::/0"
  ]
  ext_dns = [
    "9.9.9.9",
    "149.112.112.112"
  ]
}
