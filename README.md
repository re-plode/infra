# Infra

## Prerequisites

* [direnv](https://direnv.net/)
* [taskfile](https://taskfile.dev/installation)
* [OpenTofu](https://opentofu.org/)
* [Fedora CoreOS Hetzner image](https://github.com/nightspotlight/coreos-hcloud-packer)

## Getting started

```bash
# Fedora
$ go-task

# Others
$ task

$ cp .envrc.sample .envrc

$ direnv allow .

$ tofu init

$ tofu plan
```
