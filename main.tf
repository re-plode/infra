resource "cloudflare_dns_record" "replo_de_dns_a_record" {
  zone_id = local.cloudflare_replo_de_zone_id
  content = hcloud_server.internal_net.ipv4_address
  name    = "@"
  proxied = false
  ttl     = 1
  type    = "A"
}
resource "cloudflare_dns_record" "wildcard_replo_de_dns_cname_record" {
  zone_id = local.cloudflare_replo_de_zone_id
  content = "replo.de"
  name    = "*"
  proxied = false
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "mg_rcheung_com_receiving_records" {
  for_each = {
    for record in mailgun_domain.rcheung_com.receiving_records_set : record.id => {
      type     = record.record_type
      value    = record.value
      priority = record.priority
    }
  }

  zone_id  = local.cloudflare_rcheung_com_zone_id
  name     = "mg"
  type     = each.value.type
  content  = each.value.value
  priority = max(30, each.value.priority)
  proxied  = false
  ttl      = 1
}
resource "cloudflare_dns_record" "mg_rcheung_com_sending_records" {
  for_each = {
    for record in mailgun_domain.rcheung_com.sending_records_set : record.id => {
      name  = record.name
      type  = record.record_type
      value = record.value
    }
  }

  zone_id = local.cloudflare_rcheung_com_zone_id
  content = each.value.value
  name    = each.value.name
  type    = each.value.type
  proxied = false
  ttl     = 1
}
resource "cloudflare_dns_record" "mg_rcheung_com_txt_dmarc" {
  zone_id = local.cloudflare_rcheung_com_zone_id
  content = "\"v=DMARC1; p=none; pct=100; fo=1; ri=3600; rua=mailto:f0db1026@dmarc.mailgun.org,mailto:fe1b6994@inbox.ondmarc.com; ruf=mailto:f0db1026@dmarc.mailgun.org,mailto:fe1b6994@inbox.ondmarc.com;\""
  name    = "_dmarc.mg"
  proxied = false
  ttl     = 1
  type    = "TXT"
}

resource "mailgun_domain" "rcheung_com" {
  name        = "mg.rcheung.com"
  region      = "us"
  spam_action = "disabled"

  lifecycle {
    # Removing the domain might prevent me from creating a new domain
    prevent_destroy = true
  }
}

resource "mailgun_domain_credential" "noreply_rcheung_com" {
  domain   = "mg.rcheung.com"
  login    = "noreply"
  password = sensitive(data.sops_file.secrets.data["mailgun.smtp_password"])
  region   = "us"

  lifecycle {
    ignore_changes = [password]
  }
}

resource "cloudflare_dns_record" "replo_de_txt_mx" {
  for_each = tomap({
    "@"      = "brevo-code:803fa6d6251d53349cbefb857f15f2ae"
    "_dmarc" = "v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com"
  })
  zone_id = local.cloudflare_replo_de_zone_id
  content = each.value
  name    = each.key
  proxied = false
  ttl     = 1
  type    = "TXT"
}
resource "cloudflare_dns_record" "replo_de_cname_mx" {
  for_each = tomap({
    "brevo1._domainkey" = "b1.replo-de.dkim.brevo.com"
    "brevo2._domainkey" = "b2.replo-de.dkim.brevo.com"
  })
  zone_id = local.cloudflare_replo_de_zone_id
  content = each.value
  name    = each.key
  proxied = false
  ttl     = 1
  type    = "CNAME"
}

resource "tailscale_oauth_client" "github" {
  description = "github"
  scopes      = ["auth_keys"]
  tags        = ["tag:github"]
}

resource "tailscale_dns_nameservers" "dns_ns" {
  nameservers = [
    "172.254.0.1",
    "10.42.20.78"
  ]
}
resource "tailscale_dns_preferences" "dns_preferences" {
  magic_dns = false
}

data "tailscale_device" "apple_tv" {
  name = "apple-tv.tail1d86f5.ts.net"
}
resource "tailscale_device_key" "apple_tv_key" {
  device_id           = data.tailscale_device.apple_tv.node_id
  key_expiry_disabled = true
}
resource "tailscale_device_subnet_routes" "apple_tv_routes" {
  device_id = data.tailscale_device.apple_tv.node_id
  routes = [
    "10.42.10.0/24",
    "10.42.20.0/24",
    "0.0.0.0/0",
    "::/0"
  ]
}
