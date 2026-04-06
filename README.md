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
$ tofu init
$ ./bin/get-tfstate.sh
$ tofu plan
$ tofu apply
$ ./bin/put-tfstate.sh
```
