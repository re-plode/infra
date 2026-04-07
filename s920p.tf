resource "synology_container_project" "nginx" {
  name = "nginx"
  run  = true
  services = {
    nginx = {
      name           = "nginx"
      container_name = "nginx"
      user           = "root"
      restart        = "unless-stopped"
      replicas       = 1
      image          = "nginx:latest"
    }
  }
}
