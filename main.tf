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
