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

resource "cloudflare_dns_record" "replo_de_cname_return" {
  zone_id = local.cloudflare_replo_de_zone_id
  content = "return.smtp2go.net"
  name    = "em552681"
  proxied = false
  ttl     = 1
  type    = "CNAME"
}
resource "cloudflare_dns_record" "replo_de_cname_smtp2go" {
  for_each = tomap({
    "em552681"           = "return.smtp2go.net"
    "s552681._domainkey" = "dkim.smtp2go.net"
    "link"               = "track.smtp2go.net"
  })
  zone_id = local.cloudflare_replo_de_zone_id
  content = each.value
  name    = each.key
  proxied = false
  ttl     = 1
  type    = "CNAME"
}
