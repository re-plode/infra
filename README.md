# Infra

## Prerequisites

* [direnv](https://direnv.net/)
* [OpenTofu](https://opentofu.org/)
* [Fedora CoreOS Hetzner image](https://github.com/nightspotlight/coreos-hcloud-packer)

## Getting started

```bash
$ cp .envrc.sample .envrc

$ direnv allow .

$ tofu init

$ tofu plan
```
