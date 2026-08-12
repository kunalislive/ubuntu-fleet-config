# Sarvika Technologies — Ubuntu Fleet Management 

> **Ansible-based GitOps fleet management** — a single-command solution to enroll, harden, and centrally manage Ubuntu laptops/desktops across the organisation.

---

## Table of Contents

- [Overview](#overview)
- [Architecture Blueprint](#architecture-blueprint)
- [How It Works](#how-it-works)
- [How to Enroll a New Laptop](#how-to-enroll-a-new-laptop)
  - [Method A — On-Premise / VPN (Standard)](#method-a--on-premise--vpn-standard)
  - [Method B — Work From Home (VPN First)](#method-b--work-from-home-vpn-first)
- [File Structure](#file-structure)
- [What the Playbook Does](#what-the-playbook-does)
  - [1. Pre-flight Check](#1-pre-flight-check)
  - [2. Base Packages](#2-base-packages)
  - [3. AD Privilege Control (sudoers)](#3-ad-privilege-control-sudoers)
  - [4. Automatic Security Patching](#4-automatic-security-patching)
  - [5. Desktop Lockdown](#5-desktop-lockdown)
  - [6. Corporate Wallpaper](#6-corporate-wallpaper)
  - [7. Security Hardening](#7-security-hardening)
  - [8. Legal Login Banners](#8-legal-login-banners)
  - [9. Software Audit](#9-software-audit)
  - [10. Centralized Logging / SIEM (Future)](#10-centralized-logging--siem-future)
- [Requirements](#requirements)
- [Operations Cheat Sheet](#operations-cheat-sheet)
  - [Force an Immediate Update](#force-an-immediate-update)
  - [Disable a Specific Policy](#disable-a-specific-policy)
  - [Update the Corporate Wallpaper](#update-the-corporate-wallpaper)
  - [Check Ansible Cron Job Status](#check-ansible-cron-job-status)
  - [Manually Verify a Machine is Enrolled](#manually-verify-a-machine-is-enrolled)
- [Scheduled Pull (Auto-Update)](#scheduled-pull-auto-update)
- [Logs](#logs)
- [Troubleshooting & Known Issues](#troubleshooting--known-issues)
- [TODO / Roadmap](#todo--roadmap)

---

## Overview

This repository manages the **automated, zero-touch configuration** for the Sarvika Technologies Ubuntu fleet. It uses a **Hybrid GitOps Architecture**:

- **The Local Anchor (Synology NAS)** — hosts `bootstrap.sh` at `smb://172.26.3.101/softwares/ansible/ubuntu-fleet-config-main/` for secure day-1 enrollment on the internal network.
- **The Brain (GitHub)** — hosts `local.yml` (the Ansible playbook) and all corporate assets (wallpaper, policies).
- **The Execution (Endpoints)** — each enrolled laptop runs a silent cron job at **2:00 AM daily** to pull the latest configuration from GitHub and apply it automatically.
- **VPN (Exception)** — for the few employees working remotely, connecting to the Sarvika VPN makes the NAS reachable from home, using the same enrollment process as the office.

Pushing a change to GitHub is all it takes to update every managed machine in the fleet within 24 hours — no manual SSH or physical access required.

---

## Architecture Blueprint

```
┌──────────────────────────────────────────────────────────────────────┐
│                     SARVIKA IT INFRASTRUCTURE                        │
│                                                                      │
│  ┌─────────────────────┐          ┌──────────────────────────────┐   │
│  │    Synology NAS     │          │      GitHub Repository       │   │
│  │    172.26.3.101     │          │   ubuntu-fleet-config        │   │
│  │                     │          │                              │   │
│  │  bootstrap.sh       │          │   local.yml  (playbook)      │   │
│  │  (day-1 only)       │          │   files/company-wallpaper.jpg│   │
│  └──────────┬──────────┘          └──────────────┬───────────────┘   │
│             │ (office - standard)           │ nightly at 02:00       │
│             │ (VPN - exception, few WFH)    ▼                        │
│             └─────────────────────► Managed Ubuntu Laptops           │
│                                   /etc/cron.d/ansible-fleet-pull     │
│                                   → curl github → ansible-playbook   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## How It Works

```
New Ubuntu Machine
      │
      ▼
 bootstrap.sh          ← Run once (as root) on day-1
      │
      ├─ Installs Ansible (via official PPA)
      ├─ Writes /etc/cron.d/ansible-fleet-pull (daily 02:00 sync)
      └─ Downloads & runs local.yml immediately (first-time config)
             │
             ▼
         local.yml      ← Ansible playbook (idempotent, runs nightly)
             │
             ├─ Validates OS is Ubuntu
             ├─ Installs base packages (git, curl, vim, htop, openssh-server)
             ├─ Configures sudoers / AD group privileges
             ├─ Enables unattended security patching
             ├─ Locks down GNOME desktop (USB, autorun, screen lock, wallpaper)
             ├─ Hardens kernel & network (sysctl, AppArmor, auditd, fail2ban)
             ├─ Deploys legal login banners (SSH + console)
             └─ Schedules monthly software audit → syslog → log aggregator
```

---

## How to Enroll a New Laptop

>  **Policy:** `bootstrap.sh` is hosted exclusively on the internal Synology NAS and is **never distributed publicly**. All enrollments must go through the NAS — either from the office (standard) or over VPN (exception for a few WFH users).

### Method A — On-Premise (Standard — Most Users)

> Use this method when the laptop is **physically in the office**. This is the default enrollment path for the vast majority of Sarvika employees.

**Step 1 — Mount the NAS and download the bootstrap script (run as the standard user):**

```bash
gio mount smb://172.26.3.101/softwares
gio copy smb://172.26.3.101/softwares/ansible/ubuntu-fleet-config-main/bootstrap.sh ~/Downloads/bootstrap.sh
gio mount -u smb://172.26.3.101/softwares
```

**Step 2 — Switch to the local IT Admin account (`stpl`):**

```bash
su - stpl
```

**Step 3 — Execute the bootstrap:**

```bash
sudo bash /home/USERNAME/Downloads/bootstrap.sh
```

> Replace `USERNAME` with the standard user's actual home folder name.

The laptop will automatically:
1. Install Ansible from the official PPA
2. Create the nightly cron job at `/etc/cron.d/ansible-fleet-pull`
3. Download `local.yml` from GitHub
4. Apply all Sarvika security policies immediately

When complete, you will see:

```
Onboarding Complete! This laptop is now managed centrally
```

### Method B — Work From Home (VPN First)

> Use this method when the employee **cannot be physically present** in the office. The VPN must be set up **before** running the bootstrap — this makes the NAS reachable from home exactly as if on-premise.

**Step 0 — Resolve the chicken-and-egg (new machine with no VPN yet):**

IT must deliver VPN credentials and the VPN client to the employee via one of:
- Email the VPN config file + VPN client installer (e.g. OpenVPN / WireGuard)
- Ship a pre-configured USB drive with the VPN client and config
- IT admin remotes in via AnyDesk/TeamViewer to install VPN first

**Step 1 — Employee connects to Sarvika VPN:**

```bash
# Example for WireGuard
sudo wg-quick up /path/to/sarvika.conf

# Example for OpenVPN
sudo openvpn --config /path/to/sarvika.ovpn
```

Verify NAS is reachable before proceeding:

```bash
ping -c 2 172.26.3.101
```

**Step 2 — IT admin (SSH) runs Method A steps:**

Once VPN is up, the NAS is reachable and **Method A applies exactly** — the IT admin mounts the NAS, downloads `bootstrap.sh`, and executes it. The employee does not handle the script.

```bash
gio mount smb://172.26.3.101/softwares
gio copy smb://172.26.3.101/softwares/ansible/ubuntu-fleet-config-main/bootstrap.sh ~/Downloads/bootstrap.sh
gio mount -u smb://172.26.3.101/softwares
su - stpl
sudo bash /home/USERNAME/Downloads/bootstrap.sh
```

>⚠️  **Security Note:** The bootstrap script is sourced **only** from the internal NAS in both methods. It is never downloaded from a public URL, ensuring no tampered or unofficial version can be run.

---

## File Structure

```
ubuntu-fleet-config/
├── bootstrap.sh                # One-time onboarding script — installs Ansible & schedules cron
├── local.yml                   # Ansible playbook — the complete fleet configuration
├── files/
│   └── company-wallpaper.jpg   # Corporate desktop wallpaper (deployed system-wide, locked)
└── README.md                   # This file
```

---

## What the Playbook Does

### 1. Pre-flight Check

- Aborts immediately if the OS is **not Ubuntu**, preventing accidental execution on unsupported systems (Debian, CentOS, etc.).

---

### 2. Base Packages

Installs the following standard tools on every managed machine:

| Package | Purpose |
|---|---|
| `git` | Version control |
| `curl` | HTTP client / download tool |
| `htop` | Interactive process monitor |
| `vim` | Terminal text editor |
| `openssh-server` | Remote SSH access |

Also **disables `fwupd`** (firmware update daemon) to prevent uncontrolled firmware changes on endpoints.

---

### 3. AD Privilege Control (sudoers)

Deploys `/etc/sudoers.d/ad-policy` with the following rules:

| AD Group | GID | Permissions |
|---|---|---|
| `domain admins@sarvika.com` | `1405200512` | Full `sudo` (all commands) |
| `domain users@sarvika.com` | `1405200513` | Password-less `sudo` for **safe-update.sh only** |

Also deploys `/usr/local/bin/safe-update.sh` — a restricted wrapper that runs `apt update && apt upgrade -y && apt autoremove -y`. Domain users can trigger updates without full root access.

**Sudo policy hardening:**
- Session timeout: **15 minutes**
- Max password attempts: **3**
- All sudo activity logged to `/var/log/sudo.log`

---

### 4. Automatic Security Patching

Configures `/etc/apt/apt.conf.d/20auto-upgrades`:

- **Daily** package list updates
- **Daily** unattended security upgrades
- **Weekly** apt cache auto-clean

---

### 5. Desktop Lockdown

| Setting | Value |
|---|---|
| Autorun (removable media) | Disabled |
| Screen lock | Enabled |
| Screen lock delay | 5 minutes (300 s) |
| USB mass storage (`usb_storage`, `uas`) | Blacklisted via `/etc/modprobe.d/` |
| Network hotspot creation | Blocked via Polkit for domain users |
| Desktop wallpaper | Locked (users cannot change it) |

All GNOME settings are enforced via `dconf` with system-level locks at `/etc/dconf/db/local.d/locks/`, making them impossible to override from user settings.

---

### 6. Corporate Wallpaper

- Downloads `company-wallpaper.jpg` from the `files/` folder in this repository and deploys it to `/usr/share/backgrounds/`.
- Configured as the system-wide GNOME background for both light and dark modes via `dconf`.
- The background setting is **locked** — end users cannot change it even from GNOME Settings.

> ⚠️ **Known Issue:** The download URL in `local.yml` currently uses `github.com/.../blob/...` (HTML page) instead of `raw.githubusercontent.com/...` (actual file). This will cause a 404 error. See [Troubleshooting](#troubleshooting--known-issues).

---

### 7. Security Hardening

#### fail2ban (SSH brute-force protection)

| Parameter | Value |
|---|---|
| Max retries | 15 |
| Ban duration | 1 hour (3600 s) |
| Detection window | 10 minutes (600 s) |

#### auditd (kernel audit logging)

Rules deployed to `/etc/audit/rules.d/hardening.rules`:

- Watches `/etc/passwd` for write/attribute changes (`identity`)
- Watches `/etc/sudoers` and `/etc/sudoers.d/` for changes (`sudoers_change`)
- Watches `/var/log/auth.log` for changes (`auth_log`)
- Logs all `execve` syscalls (`exec_log`)

#### AppArmor

- Enforced on all available profiles (`aa-enforce /etc/apparmor.d/*`)
- Service enabled and running

#### sysctl kernel hardening (`/etc/sysctl.d/99-hardening.conf`)

| Setting | Value | Purpose |
|---|---|---|
| `net.ipv4.ip_forward` | `0` | Disable IP forwarding |
| `net.ipv6.conf.all.forwarding` | `0` | Disable IPv6 forwarding |
| `net.ipv4.tcp_syncookies` | `1` | SYN flood protection |
| `kernel.randomize_va_space` | `2` | Full ASLR |
| `net.ipv4.conf.all.accept_redirects` | `0` | Ignore ICMP redirects |
| `net.ipv4.conf.all.send_redirects` | `0` | Don't send ICMP redirects |
| `net.ipv4.conf.all.accept_source_route` | `0` | Ignore source-routed packets |
| `net.ipv4.conf.all.log_martians` | `1` | Log martian packets |
| `fs.suid_dumpable` | `0` | Disable setuid core dumps |

---

### 8. Legal Login Banners

Deploys a legal notice to:

- `/etc/issue.net` — shown to remote SSH users (pre-authentication)
- `/etc/issue` — shown on local console login
- SSH is configured to present `/etc/issue.net` via `Banner` directive in `sshd_config`

---

### 9. Software Audit

Deploys `/usr/local/bin/software-audit.sh` and schedules it via cron to run on the **1st of every month at 02:00**.

The script logs all installed software (APT packages, Snap packages, and GUI `.desktop` apps) to syslog in the format:

```
SoftwareAudit: OS=Ubuntu, Host=<hostname>, Date=<YYYY-MM-DD>, Type=<APT|Snap|GUI>, Pkg=<name>, Ver=<version>
```

Rsyslog is configured to forward all `SoftwareAudit:` messages to the log aggregator at **`192.168.1.100:514`** (UDP syslog).

---

### 10. Centralized Logging / SIEM (Future)

A commented-out rsyslog task is present in `local.yml` to forward **all** logs to a central SIEM at `siem.sarvika.com:514`. This is **not yet active** — uncomment and configure when a SIEM is available.

---

## Requirements

| Requirement | Detail |
|---|---|
| OS | Ubuntu (any version — other distros are rejected) |
| Privileges | Must be run as `root` (or via `sudo`) |
| Network | Outbound HTTPS to `raw.githubusercontent.com` |
| Ansible | Installed automatically by `bootstrap.sh` |

---

## Scheduled Pull (Auto-Update)

`bootstrap.sh` installs a cron job at `/etc/cron.d/ansible-fleet-pull` that runs **nightly at 02:00**:

```cron
0 2 * * * root curl -sfkL https://raw.githubusercontent.com/kunalislive/ubuntu-fleet-config/main/local.yml -o /tmp/local.yml && ansible-playbook /tmp/local.yml > /var/log/ansible-fleet.log 2>&1
```

This means any change pushed to `local.yml` in this repository will automatically propagate to all enrolled machines within 24 hours — no manual push required.

---

## Logs

| Log file | Contents |
|---|---|
| `/var/log/ansible-fleet.log` | Output of the nightly Ansible run |
| `/var/log/sudo.log` | All sudo command activity |
| `/var/log/auth.log` | Authentication events (watched by auditd & fail2ban) |
| syslog (`logger`) | Monthly software audit entries |

---

## Known Issues / TODO

- [ ] SIEM forwarding (`siem.sarvika.com:514`) is commented out — enable once SIEM infrastructure is in place.
- [ ] Software audit log aggregator IP (`192.168.1.100:514`) is hardcoded — consider making it a variable.
- [ ] No idempotency guard on `aa-enforce` — minor harmless warning on every run.

---

> Maintained by the IT Infrastructure team at **Sarvika Technologies**.
