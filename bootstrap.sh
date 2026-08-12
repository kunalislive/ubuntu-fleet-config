#!/bin/bash
set -e
echo "Starting IT Infrastructure Onboarding for Sarvika Technologies..."

apt update
apt install software-properties-common -y
add-apt-repository --yes --update ppa:ansible/ansible
apt install ansible -y

echo "0 2 * * * root curl -sfkL https://raw.githubusercontent.com/kunalislive/ubuntu-fleet-config/main/local.yml -o /tmp/local.yml && ansible-playbook /tmp/local.yml > /var/log/ansible-fleet.log 2>&1" > /etc/cron.d/ansible-fleet-pull
chmod 0644 /etc/cron.d/ansible-fleet-pull

curl -sfkL https://raw.githubusercontent.com/kunalislive/ubuntu-fleet-config/main/local.yml -o /tmp/local.yml
if [ ! -s /tmp/local.yml ]; then
  echo "ERROR: Failed to download local.yml — check network access to raw.githubusercontent.com"
  exit 1
fi

ansible-playbook /tmp/local.yml
echo "Onboarding Complete! This laptop is now managed centrally via GitHub."
