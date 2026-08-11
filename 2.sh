#!/bin/bash
echo "Starting IT Infrastructure Onboarding for Sarvika Technologies..."

# 1. Install Ansible and Curl
apt update
apt install software-properties-common curl -y
add-apt-repository --yes --update ppa:ansible/ansible
apt install ansible -y

# 2. Set up the daily Ansible run from the NAS Web Server
echo "0 2 * * * root curl -sL http://172.26.3.101:8001/local.yml -o /tmp/local.yml && ansible-playbook /tmp/local.yml > /var/log/ansible-nas.log 2>&1" > /etc/cron.d/ansible-fleet-pull
chmod 0644 /etc/cron.d/ansible-fleet-pull

# 3. Force the first run immediately
curl -sL http://172.26.3.101:8001/local.yml -o /tmp/local.yml
ansible-playbook /tmp/local.yml

echo "Onboarding Complete! This laptop is now managed centrally."
