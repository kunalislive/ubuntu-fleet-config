#!/bin/bash
echo "Starting IT Infrastructure Onboarding for Sarvika Technologies..."

# 1. Install dependencies
apt update
apt install software-properties-common -y
add-apt-repository --yes --update ppa:ansible/ansible
apt install ansible -y

# 2. Set up the daily cron job to pull the RAW playbook from GitHub
echo "0 2 * * * root curl -skL https://raw.githubusercontent.com/kunalislive/ubuntu-fleet-config/main/local.yml -o /tmp/local.yml && ansible-playbook /tmp/local.yml > /var/log/ansible-fleet.log 2>&1" > /etc/cron.d/ansible-fleet-pull
chmod 0644 /etc/cron.d/ansible-fleet-pull

# 3. Pull the playbook immediately for the first run
curl -skL https://raw.githubusercontent.com/kunalislive/ubuntu-fleet-config/main/local.yml -o /tmp/local.yml

# 4. Execute it
ansible-playbook /tmp/local.yml

echo "Onboarding Complete! This laptop is now managed centrally via GitHub."
