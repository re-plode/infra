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
  content = "replo.de"
  name    = "*"
  proxied = false
  ttl     = 1
  type    = "CNAME"
}

resource "mailgun_domain" "rcheung_com" {
  name          = "mg.rcheung.com"
  region        = "us"
  spam_action   = "disabled"
  smtp_password   = "${var.mailgun_smtp_password}"
  dkim_key_size   = 1024
}

resource "terraform_data" "force_run" {
  input = timestamp()

  # Comment this to force replacement
  lifecycle {
    ignore_changes = [input]
  }
}
