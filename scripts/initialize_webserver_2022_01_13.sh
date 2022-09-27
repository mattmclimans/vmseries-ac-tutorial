#!/bin/bash
apt-get update
apt install docker.io python3-pip build-essential libssl-dev libffi-dev -y --force-yes
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
cd /var/tmp
cat << EOH > docker-compose.yml
version: '3'
services:
  jenkins:
    image: pglynn/jenkins:latest
    restart: on-failure
    environment:
      JAVA_OPTS: "-Djava.awt.headless=true"
      JAVA_OPTS: "-Djenkins.install.runSetupWizard=false"
    ports:
      - "50000:50000"
      - "8080:8080"
EOH
systemctl restart docker
docker-compose up -d
