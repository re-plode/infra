# Infra

## Prerequisites

* [direnv](https://direnv.net/)
* [taskfile](https://taskfile.dev/installation)
* [OpenTofu](https://opentofu.org/)

## Getting started

```sh
$ task
$ cp .envrc.sample .envrc
$ direnv allow .
$ sops edit config/secrets.enc.json
$ tofu init
$ tofu plan
$ tofu apply
```
