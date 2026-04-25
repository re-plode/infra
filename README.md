# Infra

## Prerequisites

* [direnv](https://direnv.net/)
* [taskfile](https://taskfile.dev/installation)
* [OpenTofu](https://opentofu.org/)
* [Ansible](https://docs.ansible.com)

## Getting started

```sh
$ task
$ cp .envrc.sample .envrc
$ direnv allow .
$ sops edit config/secrets.enc.json
$ cd terraform
$ tofu init
$ tofu plan
$ tofu apply
$ cd ../ansible
$ ansible-playbook -i hosts.yml remote.yml
```
