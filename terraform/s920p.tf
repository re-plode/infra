resource "terraform_data" "force_run" {
  input = timestamp()

  # Comment this to force replacement
  lifecycle {
    ignore_changes = [input]
  }
}

resource "synology_filestation_file" "var" {
  path    = "/var/traefik/config/dsm.toml"
  content = <<EOT
[http]
  [http.routers]
    [http.routers.router0]
      entryPoints = ["websecure"]
      service = "service-photos"
      rule = "Host(`photos.replo.de`)"
      [http.routers.router0.tls]
        certResolver = "cloudflare"

    [http.routers.router1]
      entryPoints = ["websecure"]
      service = "service-dsm"
      rule = "Host(`dsm.replo.de`)"
      [http.routers.router1.tls]
        certResolver = "cloudflare"

  [http.services]
    [http.services.service-dsm]
      [http.services.service-dsm.loadBalancer]
        [[http.services.service-dsm.loadBalancer.servers]]
          url = "http://10.42.20.78:5000/"

    [http.services.service-photos]
      [http.services.service-photos.loadBalancer]
        [[http.services.service-photos.loadBalancer.servers]]
          url = "http://10.42.20.78:5080/"
EOT
}
