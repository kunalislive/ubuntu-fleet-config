#!/bin/bash
echo "Starting IT Infrastructure Onboarding for Sarvika Technologies..."

# 1. Install Ansible (using the exact PPA commands)
apt update
apt install software-properties-common cifs-utils -y
add-apt-repository --yes --update ppa:ansible/ansible
apt install ansible -y

# 2. Set up the daily Ansible run from the NAS
echo "0 2 * * * root mkdir -p /mnt/it-config && mount -t cifs //192.168.1.50/IT-Config /mnt/it-config -o guest && ansible-playbook /mnt/it-config/local.yml > /var/log/ansible-nas.log 2>&1 && umount /mnt/it-config" > /etc/cron.d/ansible-fleet-pull
chmod 0644 /etc/cron.d/ansible-fleet-pull

# 3. Force the first run immediately
mkdir -p /mnt/it-config
mount -t cifs //192.168.1.50/IT-Config /mnt/it-config -o guest
ansible-playbook /mnt/it-config/local.yml
umount /mnt/it-config

echo "Onboarding Complete! This laptop is now managed centrally."
