# https://github.com/crowdsecurity/cs-firewall-bouncer/issues/32#issuecomment-1060890534
FROM fedora:40

RUN <<-EOF
  dnf -y update
  dnf -y install curl
  curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.rpm.sh | bash
  dnf -y install crowdsec-firewall-bouncer-iptables
EOF

ENTRYPOINT crowdsec-firewall-bouncer -c /crowdsec-firewall-bouncer.yaml
